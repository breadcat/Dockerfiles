#!/bin/bash

# functions
function func_dir_find {
	find "$directory_home" -maxdepth 3 -mount -type d -name "$1" 2>/dev/null
}
function func_rclone_remote {
	$rclone_command listremotes | grep "$1"
}
function func_check_running_as_root {
	if [ "$EUID" -ne 0 ]
	then
		echo "Please run as root"
		exit 0
	fi
}
function password_manager {
	case "$1" in
		addr) rbw get --full "$2" | awk '/URI\:/ {print $2}' ;;
		full) rbw get --full "$2" ;;
		pass) rbw get "$2" ;;
		sync) rbw sync ;;
		user) rbw get --full "$2" | awk '/Username\:/ {print $2}' ;;
		*) rbw get "$2" ;;
	esac
}
function func_backup_archive {
	rclone_remote=$(func_rclone_remote backups)
	working_directory=$(func_dir_find backups)/archives
	echo "$working_directory"
	if [ -z "$*" ]
	then
		echo Creating archives...
		# build folder array?
		cd "$(mktemp -d)" || exit
		for i in "config" "vault"
		do
			tar -cJf "backup-$i-$(date +%F-%H%M).tar.xz" --ignore-failed-read "$directory_home/$i"
		done
		echo "Sending via rclone..."
		for i in *
		do
			du -h "$i"
			$rclone_command move "$i" "$rclone_remote"/archives/
		done
		echo Cleaning up...
		rm -r "$PWD"
		echo Done!
	else
		echo Creating single archive...
		cd "$(mktemp -d)" || exit
		tar -cJf "backup-$1-$(date +%F-%H%M).tar.xz" --ignore-failed-read "$directory_home/$1"
		echo "Sending via rclone..."
		for i in *
		do
			du -h "$i" && $rclone_command move "$i" "$rclone_remote"/archives/
		done
		echo Cleaning up...
		rm -r "$PWD"
		echo Done!
	fi
}
function func_backup_borg {
	# https://opensource.com/article/17/10/backing-your-machines-borg
	working_directory=$(func_dir_find backups)/borg
	echo "$working_directory"
}
function func_duolingo_streak {
	# check api is installed
	[[ -d "$(func_dir_find config)/duolingo" ]] || git clone https://github.com/KartikTalwar/Duolingo.git "$(func_dir_find config)/duolingo"
	# cd to git dir to include module
	cd "$(func_dir_find config)/duolingo" || return
	# write script
	password_manager sync
	{
		printf "#!/usr/bin/env python3\\n\\n"
		printf "import duolingo\\n"
		printf "lingo  = duolingo.Duolingo('%s', password='%s')\\n" "$(password_manager user duolingo)" "$(password_manager pass duolingo)"
		printf "lingo.buy_streak_freeze()"
	} > "streak-freeze.py"
	# run and remove script
	python "streak-freeze.py"
	rm "streak-freeze.py"
}
function func_create_docker {
	cd "$directory_script" || exit
	# write env file, overwriting any existing
	password_manager sync
	{
		printf "DOMAIN=%s\\n" "$domain"
		printf "PUID=%s\\n" "$(id -u)"
		printf "PGID=%s\\n" "$(id -g)"
		printf "TZ=%s\\n" "$(cat /etc/timezone)"
		printf "CONFDIR=%s\\n" "$(func_dir_find config)"
		printf "POOLDIR=%s\\n" "$(func_dir_find media)"
		printf "SYNCDIR=%s\\n" "$(func_dir_find vault)"
		printf "RCLONE_REMOTE_MEDIA=%s\\n" "$(func_rclone_remote media)"
		printf "WG_WEBUI_PASS=%s\\n" "$(password_manager pass 'wireguard admin')"
		printf "WG_PRIVKEY=%s\\n" "$(password_manager pass 'wireguard private key')"
		printf "DBPASSWORD=%s\\n" "$(password_manager pass postgresql)"
	} > "$directory_script/.env"
	# clean up existing stuff
	echo Cleaning up existing docker files
	for i in volume image system network
	do
		docker "$i" prune -f
	done
	docker system prune -af
	# make network, if not existing
	if ! printf "%s" "$(docker network ls)" | grep -q "proxy"
	then
		echo Creating docker network
		docker network create proxy
	fi
	# start containers
	echo Starting docker containers
	docker-compose up -d --remove-orphans
	# delete temporary env file
	if [[ -f "$directory_script/.env" ]]
	then
		echo Deleting detected env file
		rm "$directory_script/.env"
	fi
	# clean up, again
	docker volume prune -f
}
function func_beets {
	# exists for working around quirks with running beets through a docker container
	func_check_running_as_root
	# make directories
	for i in export staging; do mkdir "$(func_dir_find downloads)/$i"; done
	if ! printf "%s" "$(docker ps -a | grep beets)" | grep -q "Up"
	then
		echo Starting beets container, and waiting...
		docker start beets
		sleep 5s
	fi
	docker exec -it beets bash
	echo Moving files
	$rclone_command move "$(func_dir_find export)" "$(func_rclone_remote media)"/audio/ --verbose
	echo Resetting permissions
	chown -R "$username":"$username" "$(func_dir_find export)"
	chown -R "$username":"$username" "$(func_dir_find staging)"
	echo Cleaning folders
	find "$(func_dir_find export)" -type d -empty -delete
	find "$(func_dir_find staging)" -type d -empty -delete
	echo Stopping beets container
	docker stop beets
	echo Cleaning old files
	find "$(func_dir_find beets)" -type f -not -name 'config.yaml' -delete
}
function func_logger {
	password_manager sync
	# git configuruation
	git config --global user.email "$(password_manager user email)"
	git config --global user.name "$username"
	git config pack.windowMemory 10m
	git config pack.packSizeLimit 20m
	# specify working points
	git_directory="$(func_dir_find logger)"
	file_git_log="$git_directory/media.log"
	log_command="git --git-dir=$git_directory/.git --work-tree=$git_directory"
	log_remote=$(func_rclone_remote media)
	if [ ! -e "$git_directory" ]
	then
		mkdir "$git_directory" # make log directory
	fi
	if [ ! -e "$git_directory/.git" ]
	then
		$log_command init # initialise git repo
	fi
	if [ -e "$file_git_log.xz" ]
	then
		xz -d "$file_git_log.xz" # if xz archive exists, decompress
	fi
	if [ -e "$file_git_log" ]
	then
		rm "$file_git_log"
	fi
	$rclone_command ls "$log_remote" | sort -k2 > "$file_git_log" # create log
	$rclone_command size "$log_remote" >> "$file_git_log" # append size
	$log_command add "$file_git_log" # add log file
	$log_command commit -m "Update: $(date +%F)" # commit to repo, datestamped
	if [ -e "$file_git_log.xz" ]
	then
		rm "$file_git_log.xz"
	fi
	xz "$file_git_log" # compress log
	$log_command gc --aggressive --prune # compress repo
}
function func_magnet {
	cd "$(func_dir_find vault)" || exit
	func_sshfs_mount
	mag2tor_script_path="$(func_dir_find config)/magnet2torrent/Magnet_To_Torrent2.py"
	if [ ! -f "$mag2tor_script_path" ]
	then
		echo "script not found, downloading"
		git clone "https://github.com/danfolkes/Magnet2Torrent.git" "$(func_dir_find config)/magnet2torrent"
	fi
	shopt -s nullglob
	echo "processing magnets"
	for i in *.magnet
	do
		magnet_source="$(cat "$i")"
		timeout 5m python "$mag2tor_script_path" -m "$magnet_source" -o "$(func_dir_find downloads)/watch/"
		rm "$i"
	done
	echo "processing torrents"
	for i in *.torrent
	do
		mv -v "$i" "$(func_dir_find downloads)/watch/"
	done
	echo "cleaning up tmp directory"
	find /tmp/ -type d -empty -delete
}
function func_payslip {
	# depends on: getmail4 mpack qpdf
	directory_temp="$(mktemp -d)"
	cd "$directory_temp" || exit
	mkdir {cur,new,tmp}
	# write config file
	password_manager sync
	{
		printf "[retriever]\\n"
		printf "type = SimpleIMAPSSLRetriever\\n"
		printf "server = %s\\n" "$(password_manager full email | awk -F: '/Incoming/ {gsub(/ /,""); print $2}')"
		printf "username = %s\\n" "$(password_manager user email)"
		printf "port = 993\\n"
		printf "password = %s\\n\\n" "$(password_manager pass email)"
		printf "[destination]\\n"
		printf "type = Maildir\\n"
		printf "path = %s/\\n" "$directory_temp"
	} > getmailrc
	getmail --getmaildir "$directory_temp"
	cd new || exit
	grep "$(password_manager user payslip)" ./* | cut -f1 -d: | uniq | xargs munpack -f
	for i in *.PDF
	do
		mv "$i" "$(func_dir_find paperwork)/"
	done
	# decrypt payslip file
	cd "$(func_dir_find paperwork)" || exit
	for i in *.PDF
	do
		fileProtected=0
		qpdf "$i" --check || fileProtected=1
		if [ $fileProtected == 1 ]
		then
			parsed_name="$(printf "%s" "$i" | awk -FX '{print substr($3,5,4) "-" substr($3,3,2) "-" substr($3,1,2) ".pdf"}')"
			qpdf --password="$(password_manager pass payslip)" --decrypt "$i" "personal/workplace/wages/$parsed_name" && rm "$i"
		fi
	done
	# clean up temp directory
	rm -r "$directory_temp"
}
function func_permissions {
	func_check_running_as_root
	chown "$username":"$username" "$directory_script/rclone.conf"
}
function func_media_sort {
	func_sshfs_mount
	if [ ! -x "$(command -v media-sort)" ] # not installed
	then
		echo media-sort not installed. Installing...
		func_check_running_as_root
		curl https://i.jpillora.com/media-sort | bash
	fi
	dir_import=$(func_dir_find downloads)/files/complete/
	if [[ -d "$dir_import" ]]
	then
		dir_tv=$(func_dir_find media)/videos/television
		dir_mov=$(func_dir_find media)/videos/movies
		temp_tv="{{ .Name }}/{{ .Name }} S{{ printf \"%02d\" .Season }}E{{ printf \"%02d\" .Episode }}{{ if ne .ExtraEpisode -1 }}-{{ printf \"%02d\" .ExtraEpisode }}{{end}}.{{ .Ext }}"
		temp_mov="{{ .Name }} ({{ .Year }})/{{ .Name }}.{{ .Ext }}"
		media-sort --action copy --concurrency 1 --accuracy-threshold 90 --tv-dir "$dir_tv" --movie-dir "$dir_mov" --tv-template "$temp_tv" --movie-template "$temp_mov" --recursive --overwrite-if-larger "$dir_import"

	else
		printf "Import directory not found.\\n"
		exit 0
	fi
}
function func_rclone_mount {
	echo rclone mount checker
	# check allow_other in fuse.conf
	if ! grep -q "^user_allow_other$" /etc/fuse.conf
	then
		echo user_allow_other not found in fuse.conf
		func_check_running_as_root
		echo Appending to file.
		echo "user_allow_other" >> /etc/fuse.conf
		echo Please restart the script.
		exit 0
	fi
	for i in backups media paperwork pictures unsorted
	do
		mount_point="$directory_home/$i"
		if [[ -f "$mount_point/.mountcheck" ]]
		then
			echo "$i" still mounted
		else
			mount_points_remounted=true
			echo "$i" not mounted
			echo force unmounting
			fusermount -uz "$mount_point"
			echo sleeping && sleep 3
			echo mounting
			$rclone_command mount "drive-$i": "$directory_home/$i" --allow-other --allow-non-empty --daemon --log-file "$(func_dir_find config)/logs/rclone-$i.log"
		fi
		if [ "$mount_points_remounted" = true ] ; then
			echo restarting docker containers
			for j in "${docker_restart[@]}"
			do
				docker restart "$j"
			done
		fi
	done
}
function func_sshfs_mount {
	# check for mount
	printf "sshfs mount checker... "
	seedbox_mount="$(func_dir_find downloads)"
	if [[ -d "$seedbox_mount/files" ]]
	then
		printf "exists.\\n"
	else
		password_manager sync
		# determine credentials
		seedbox_provider=$(password_manager addr seedbox | cut -f2-3 -d.)
		seedbox_username=$(password_manager user seedbox)
		seedbox_password=$(password_manager pass seedbox)
		seedbox_host="$seedbox_username.$seedbox_provider"
		printf "missing.\\nre-mounting"
		fusermount -uz "$seedbox_mount"
		printf "%s" "$seedbox_password" | sshfs "$seedbox_username@$seedbox_host":/ "$seedbox_mount" -o password_stdin -o allow_other
	fi
}
function func_status {
	status_uptime=$(( $(cut -f1 -d. </proc/uptime) / 86400 ))
	{
		printf -- "---\\ntitle: Status\\nlayout: single\\n---\\n\\n"
		printf "*Generated on %(%Y-%m-%d at %H:%M)T*\\n\\n" -1
		printf "* Uptime: %s Day%s\\n" "$status_uptime" "$(if (("$status_uptime">1)); then echo s; fi)"
		printf "* CPU Load: %s\\n" "$(cut -d" " -f1-3 < /proc/loadavg)"
		printf "* Users: %s\\n" "$(uptime | grep -oP '.{3}user' | sed 's/\user//g' | xargs)"
		printf "* RAM Usage: %s%%\\n" "$(printf "%.0f" "$(free | awk '/Mem/ {print $3/$2 * 100.0}')")"
		printf "* Swap Usage: %s%%\\n" "$(printf "%.0f" "$(free | awk '/Swap/ {print $3/$2 * 100.0}')")"
		printf "* Root Usage: %s\\n" "$(df / | awk 'END{print $5}')"
		printf "* Downloads Usage: %s\\n" "$(df | awk '/downloads/ {print $5}')"
		printf "* Cloud Usage: %s\\n" "$(git --git-dir="$(func_dir_find logger)/.git" show | awk 'END{print $3" "$4}')"
		printf "* [Dockers](https://github.com/breadcat/Dockerfiles): %s\\n" "$(docker ps -q | wc -l)/$(docker ps -aq | wc -l)"
		printf "* Packages: %s\\n" "$(dpkg -l | grep ^ii -c)"
		printf "* Monthly Data: %s\\n\\n" "$(vnstat -m --oneline | cut -f11 -d\;)"
		printf "Hardware specifications themselves are covered on the [hardware page](/hardware/#server).\\n"
	} > "$(func_dir_find blog."$domain")/content/status.md"
}
function func_weight {
	# variables
	if [ -n "$2" ]
	then
		if [ "$2" = "date" ]
		then
			weight_filename="$(func_dir_find blog."$domain")/content/weight.md"
			page_source="$(head -n -1 "$weight_filename")"
			previous_date="$(printf %s "$page_source" | awk -F, 'END{print $1}')"
			todays_date="$(date +%F)"
			sequence_count="$(( ($(date --date="$todays_date" +%s) - $(date --date="$previous_date" +%s) )/(60*60*24) ))"
			# operation
			{
				printf "%s\\n" "$page_source"
				printf "%s" "$(for i in $(seq $sequence_count); do printf "%s,\\n" "$(date -d "$previous_date+$i day" +%F)"; done)"
				printf "\\n</pre></details>"
			} > "$weight_filename"
			exit 0
		else
			year=$2
		fi
	else
		year=$(date +%Y)
	fi
	weight_filename="$(func_dir_find blog."$domain")/content/weight.md"
	# cd to temporary directory
	cd "$(mktemp -d)" || exit
	# pull raw data from source
	weight_rawdata="$(awk '/<pre>/{flag=1; next} /<\/pre>/{flag=0} flag' "$weight_filename" | sort -u)"
	printf "%s" "$weight_rawdata" | grep "^$year-" > temp.dat
	weight_dateinit="$(awk '/date:/ {print $2}' "$weight_filename")"
	# draw graph
	gnuplot <<- EOF
		set grid
		set datafile separator comma
		set xlabel "Month"
		set xdata time
		set timefmt "%Y-%m-%d"
		set xtics format "%b"
		set ylabel "Weight (kg)"
		set key off
		set term svg font 'sans-serif,12'
		set sample 50
		set output "temp.svg"
		plot "temp.dat" using 1:2 smooth cspline with lines
	EOF
	# compress graph
	svgo -i "temp.svg" --multipass -o "temp.min.svg" -q
	# write page
	{
		printf -- "---\\ntitle: Weight\\nlayout: single\\ndate: %s\\nlastmod: %(%Y-%m-%dT%H:%M:00)T\\n---\\n\\n" "$weight_dateinit" -1
		printf "%s\\n\\n%s graph\\n\\n" "$(cat temp.min.svg)" "$year"
		printf "<details><summary>Raw data</summary>\\n<pre>\\n%s\\n</pre></details>" "$weight_rawdata"

	} > "$weight_filename"
	# clean up
	rm -r "$PWD"
}
function func_dedupe_remote {
	dests=$(func_rclone_remote "$rclone_core" | wc -l)
	for i in $(seq "$dests")
	do
		remote=$(func_rclone_remote "$rclone_core" | grep "$i")
		echo Deduplicating "$remote"
		$rclone_command dedupe --dedupe-mode newest "$remote" --log-file "$(func_dir_find config)/logs/rclone-dupe-$(date +%F-%H%M).log"
	done
}
function func_sync_remotes {
	source=$(func_rclone_remote "$rclone_core" | sed 1q)
	dests=$(func_rclone_remote "$rclone_core" | wc -l)
	for i in $(seq 2 "$dests")
	do
		dest=$(func_rclone_remote "$rclone_core" | grep "$i")
		echo Syncing "$source" to "$dest"
		$rclone_command sync "$source" "$dest" --drive-server-side-across-configs --drive-stop-on-upload-limit --verbose --log-file "$(func_dir_find config)/logs/rclone-sync-$(date +%F-%H%M).log"
	done
}
function func_update {
	func_check_running_as_root
	if [[ $distro =~ "Debian" ]]
	then
		# Update Debian
		export DEBIAN_FRONTEND=noninteractive
		apt-get update
		apt-get dist-upgrade -y
		apt-get autoremove --purge -y
		apt-get clean
		if [ -x "$(command -v yt-dlp)" ]
		then
			yt-dlp -U
		fi
		if [ -x "$(command -v rclone)" ]
		then
			curl --silent "https://rclone.org/install.sh" | bash
		fi
	elif [[ $distro =~ "Arch" ]]
	then
		# Update Archlinux
		if [ -x "$(command -v paru)" ]
		then
			paru -Syu --noconfirm
		else
			pacman -Syu --noconfirm
		fi
	else
		echo "Who knows what you're running"
	fi
	# Update remaining applications
	if [ -f "$directory_home/.config/retroarch/lrcm/lrcm" ]
	then
		"$directory_home/.config/retroarch/lrcm/lrcm" update
	fi
	find "$(func_dir_find config)" -maxdepth 2 -name ".git" -type d | sed 's/\/.git//' | xargs -P10 -I{} git -C {} pull
	if [ -x "$(command -v we-get)" ]
	then
		echo "Updating we-get..."
		pip3 install --upgrade git+https://github.com/rachmadaniHaryono/we-get
	fi
	if [ -x "$(command -v media-sort)" ]
	then
		echo "Updating media-sort..."
		cd "/usr/local/bin" || return
		curl https://i.jpillora.com/media-sort | bash
	fi
	if [ -x "$(command -v duplicacy)" ]
	then
		dupli_installed="$(duplicacy | awk '/VERSION/ && $0 != "" { getline; print $1}')"
		dupli_available="$(curl -s https://api.github.com/repos/gilbertchen/duplicacy/releases/latest | jq -r '.tag_name' | tr -d '[:alpha:]')"
		if [ "$dupli_installed" != "$dupli_available" ]
		then
			echo Updating Duplicacy
			wget "$(curl -sL https://api.github.com/repos/gilbertchen/duplicacy/releases/latest | jq -r '.assets[].browser_download_url' | grep linux_x64)" -O "/usr/local/bin/duplicacy"
		fi
	fi
	if [ -x "$(command -v plowmod)" ]
	then
		echo "Updating plowshare..."
		su -c "plowmod -u" -s /bin/sh "$username"
		chown -R "$username":"$username" "$directory_home/.config/plowshare"
	fi
}
function main {
	export XZ_OPT=-e9
	distro="$(awk -F'"' '/^NAME/ {print $2}' /etc/os-release)"
	username="$(logname)"
	directory_home="/home/$username"
	domain="$(awk -F'"' '/domain/ {print $2}' "$(func_dir_find traefik)/traefik.toml")"
	directory_script="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
	rclone_command="rclone --config=$directory_script/rclone.conf"
	rclone_core="gdrive"
	docker_restart=("cbreader" "syncthing")
	case "$1" in
		archive) func_backup_archive "$@" ;;
		beets) func_beets ;;
		borg) func_backup_borg ;;
		dedupe) func_dedupe_remote ;;
		docker) func_create_docker ;;
		duolingo) func_duolingo_streak ;;
		logger) func_logger ;;
		magnet) func_magnet ;;
		payslip) func_payslip ;;
		permissions) func_permissions ;;
		rclone) func_rclone_mount ;;
		sort) func_media_sort ;;
		sshfs) func_sshfs_mount ;;
		status) func_status ;;
		sync) func_sync_remotes ;;
		update) func_update ;;
		weight) func_weight "$@" ;;
		*) echo "$0" && awk '/^function main/,EOF' "$0" | awk '/case/{flag=1;next}/esac/{flag=0}flag' | awk -F"\t|)" '{print $3}' | tr -d "*" | sort | xargs ;;
	esac
}

main "$@"
