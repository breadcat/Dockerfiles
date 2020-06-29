#!/bin/bash

# functions
function func_available_options {
	sed -n '/^\tcase/,/\tesac$/p' "$0" | cut -f1 -d")" | sed '1d;$d' | sort | tr -d "*" | xargs
	}
function func_plural {
	if (("$1">1))
	then
		echo s
	fi
	}
function func_dir_find {
	find "$directory_home" -maxdepth 3 -mount -type d -name "$1"
	}
function func_domain_find {
	file_config_traefik="$(func_dir_find config)/traefik/traefik.toml"
	awk -F'"' '/domain/ {print $2}' "$file_config_traefik"
	}
function func_git_config {
	git config --global user.email "$username@$(func_domain_find)"
	git config --global user.name "$username"
	git config pack.windowMemory 10m
	git config pack.packSizeLimit 20m
	}
function func_docker_env_delete {
	if [[ -f "$directory_script/.env" ]]
	then
		echo Deleting detected env file
		rm "$directory_script/.env"
	fi
	}
function func_docker_env_write {
	{
	printf "NAME=%s\\n" "$username"
	printf "PASS=%s\\n" "$docker_password"
	printf "DOMAIN=%s\\n" "$(func_domain_find)"
	printf "PUID=%s\\n" "$(id -u)"
	printf "PGID=%s\\n" "$(id -g)"
	printf "TZ=%s\\n" "$(cat /etc/timezone)"
	printf "HOMEDIR=%s\\n" "$directory_home"
	printf "CONFDIR=%s\\n" "$(func_dir_find config)"
	printf "DOWNDIR=%s\\n" "$(func_dir_find downloads)"
	printf "POOLDIR=%s\\n" "$(func_dir_find media)"
	printf "SYNCDIR=%s\\n" "$(func_dir_find vault)"
	printf "WORKDIR=%s\\n" "$(func_dir_find paperwork)"
	printf "RCLONE_REMOTE_MEDIA=%s\\n" "$(func_rclone_remote media)"
	printf "RCLONE_REMOTE_WORK=%s\\n" "$(func_rclone_remote work)"
	} > "$directory_script/.env"
	}
function func_payslip_config_write {
	{
	printf "[retriever]\\n"
	printf "type = SimpleIMAPSSLRetriever\\n"
	printf "server = imap.yandex.com\\n"
	printf "username = %s\\n" "$payslip_username"
	printf "port = 993\\n"
	printf "password = %s\\n\\n" "$payslip_password"
	printf "[destination]\\n"
	printf "type = Maildir\\n"
	printf "path = %s/\\n" "$directory_temp"
	} > getmailrc
	}
function func_payslip_decrypt {
	cd "$(func_dir_find paperwork)" || exit
	for i in *.pdf
	do
		fileProtected=0
		qpdf "$i" --check || fileProtected=1
		if [ $fileProtected == 1 ]
		then
			parsed_name=$(printf "%s" "$i" | cut -d"-" -f"4-6")
			qpdf --password="$payslip_encryption" --decrypt "$i" "personal/workplace/wages/$parsed_name" && rm "$i"
		fi
	done
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
function func_include_credentials {
	# shellcheck source=/home/peter/vault/src/dockerfiles/credentials.db
	source "$directory_script/credentials.db"
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
			tar -cJf "backup-$i-$(date +%Y-%m-%d-%H%M).tar.xz" --ignore-failed-read "$directory_home/$i"
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
		tar -cJf "backup-$1-$(date +%Y-%m-%d-%H%M).tar.xz" --ignore-failed-read "$directory_home/$1"
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
function func_update_arch {
	if [ -x "$(command -v yay)" ]
	then
		yay -Syu --noconfirm
	else
		pacman -Syu --noconfirm
	fi
	}
function func_update_debian {
	export DEBIAN_FRONTEND=noninteractive
	apt-get update
	apt-get dist-upgrade -y
	apt-get autoremove --purge -y
	apt-get clean
	if [ -x "$(command -v youtube-dl)" ]
	then
		youtube-dl -U
	fi
	if [ -x "$(command -v rclone)" ]
	then
		curl --silent "https://rclone.org/install.sh" | bash
	fi
	}
function func_update_remaining {
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
		cd /usr/local/bin
		curl https://i.jpillora.com/media-sort | bash
	fi
	if [ -x "$(command -v duplicacy)" ]
	then
		dupli_installed=$(duplicacy | awk '/VERSION/ && $0 != "" { getline; print $1}')
		dupli_available=$(curl -s https://api.github.com/repos/gilbertchen/duplicacy/releases/latest | jq -r '.tag_name' | tr -d '[:alpha:]')
		if [ $dupli_installed != $dupli_available ]
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
function func_backup_borg {
	# https://opensource.com/article/17/10/backing-your-machines-borg
	working_directory=$(func_dir_find backups)/borg
	echo "$working_directory"
	}
function func_duolingo_streak {
	# check api is installed
	[[ -d "$(func_dir_find config)/duolingo" ]] || git clone https://github.com/KartikTalwar/Duolingo.git "$(func_dir_find config)/duolingo"
	# include username:password variables
	func_include_credentials
	# cd to git dir to include module
	cd "$(func_dir_find config)/duolingo"
	# write script per user
	for i in "${duolingo[@]}"
	do
		# split variables
		username=$(echo "$i" | cut -f1 -d:)
		password=$(echo "$i" | cut -f2 -d:)
		# write script
		{
		printf "#!/usr/bin/env python3\\n\\n"
		printf "import duolingo\\n"
		printf "lingo  = duolingo.Duolingo(\'%s\', password=\'%s\')\\n" "$username" "$password"
		printf "lingo.buy_streak_freeze()"
		} > "$username.py"
		# run and remove script
		python "$username.py"
		rm "$username.py"
	done
	}
function func_create_docker {
	cd "$directory_script" || exit
	func_docker_env_delete
	func_include_credentials
	# write env file
	func_docker_env_write
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
	func_docker_env_delete
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
	func_git_config
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
	$log_command commit -m "Update: $(date +%Y-%m-%d)" # commit to repo, datestamped
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
		echo script not found, downloading
		git clone "https://github.com/danfolkes/Magnet2Torrent.git" "$(func_dir_find config)/magnet2torrent"
	fi
	shopt -s nullglob
	echo "processing magnets"
	for i in *.magnet
	do
		magnet_source="$(cat "$i")"
		timeout 5m python "$mag2tor_script_path" -m "$magnet_source" -o "$(func_dir_find downloads)/remote/watch/"
		rm "$i"
	done
	echo "processing torrents"
	for i in *.torrent
	do
		mv -v "$i" "$(func_dir_find downloads)/remote/watch/"
	done
	}
function func_payslip {
	# depends on: getmail4 mpack qpdf
	directory_temp="$(mktemp -d)"
	func_include_credentials
	cd "$directory_temp" || exit
	mkdir {cur,new,tmp}
	func_payslip_config_write
	getmail --getmaildir "$directory_temp"
	cd new || exit
	grep "$payslip_sender" ./* | cut -f1 -d: | uniq | xargs munpack -f
	for i in *.pdf
	do
		mv "$i" "$(func_dir_find paperwork)/"
	done
	func_payslip_decrypt
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
	dir_import=$(func_dir_find remote)/files/complete/
	if [[ -d "$dir_import" ]]
	then
		dir_tv=$(func_dir_find media)/videos/television
		dir_mov=$(func_dir_find media)/videos/movies
		temp_tv="{{ .Name }}/{{ .Name }} S{{ printf \"%02d\" .Season }}E{{ printf \"%02d\" .Episode }}{{ if ne .ExtraEpisode -1 }}-{{ printf \"%02d\" .ExtraEpisode }}{{end}}.{{ .Ext }}"
		temp_mov="{{ .Name }} ({{ .Year }})/{{ .Name }}.{{ .Ext }}"
		media-sort --action copy --concurrency 1 --accuracy-threshold 90 --tv-dir "$dir_tv" --movie-dir "$dir_mov" --tv-template "$temp_tv" --movie-template "$temp_mov" --recursive --overwrite-if-larger "$dir_import"
		func_junk_clean
	else
		printf "Import directory not found.\n"
		exit 0
	fi
	}
function func_junk_clean {
	working_directory=$(func_dir_find remote)/files/complete/
	if [[ -d "$working_directory" ]]
	then
		find "$working_directory" -type f -iname "* poster.jpg" -delete
		find "$working_directory" -type f -iname "*.nfo" -delete
		find "$working_directory" -type f -iname "*.url" -delete
		find "$working_directory" -type f -iname "*.website" -delete
		find "$working_directory" -type f -iname "*downloaded from*" -delete
		find "$working_directory" -type f -iname "*sample*" -delete
		find "$working_directory" -type f -iname "*yify*jpg" -delete
		find "$working_directory" -type f -iname "*yts*jpg" -delete
		find "$working_directory" -type f -iname "ahashare*" -delete
		find "$working_directory" -type f -iname "encoded by*" -delete
		find "$working_directory" -type f -iname "cover*.jpg" -delete
		find "$working_directory" -type f -iname "folder.jpg" -delete
		find "$working_directory" -type f -iname "how to play*" -delete
		find "$working_directory" -type f -iname "rarbg*" -delete
		find "$working_directory" -type d -iname 'featurettes' -exec rm -r {} +
		find "$working_directory" -type d -iname 'sample' -exec rm -r {} +
		find "$working_directory" -type d -iname 'screens' -exec rm -r {} +
		find "$working_directory" -type d -iname 'screenshot*' -exec rm -r {} +
		find "$working_directory" -type d -empty -delete
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
			echo "$i" not mounted
			echo force unmounting
			fusermount -uz "$mount_point"
			echo sleeping
			sleep 5
			echo mounting
			$rclone_command mount "drive-$i": "$directory_home/$i" --allow-other --allow-non-empty --daemon --log-file "$(func_dir_find config)/logs/rclone-$i.log"
			echo restarting docker containers
			for j in "${docker_restart[@]}"
			do
				docker restart "$j"
			done
		fi
	done
	if ls "$directory_script"/rclone.sync-conflict* 1> /dev/null 2>&1
	then
		echo removing sync-conflict files
		rm -r "$directory_script"/rclone.sync-conflict*
	fi
	}

function func_sshfs_mount {
	func_include_credentials
	printf "sshfs mount checker... "
	seedbox_host="$seedbox_username.seedbox.io"
	seedbox_mount="$(func_dir_find downloads)/remote"
	if [[ -d "$seedbox_mount/files" ]]
	then
		printf "exists.\n"
	else
		printf "missing.\nre-mounting"
		fusermount -uz "$seedbox_mount"
		printf "%s" "$seedbox_password" | sshfs "$seedbox_username@$seedbox_host":/ "$seedbox_mount" -o password_stdin -o allow_other
	fi
	}

function func_status {
	status_filename=$(func_dir_find blog.$(func_domain_find))/content/status.md
	status_timestamp="$(date +%Y-%m-%d) at $(date +%H:%M)"
	status_uptime=$(( $(cut -f1 -d. </proc/uptime) / 86400 ))
	status_cpuavgs=$(cut -d" " -f1-3 < /proc/loadavg)
	status_users=$(uptime | grep -oP '.{3}user' | sed 's/\user//g' | xargs)
	status_ram=$(printf "%.0f" "$(free | awk '/Mem/ {print $3/$2 * 100.0}')")
	status_swap=$(printf "%.0f" "$(free | awk '/Swap/ {print $3/$2 * 100.0}')")
	status_rootuse=$(df / | awk 'END{print $5}')
	status_dluse=$(df | awk '/downloads/ {print $5}')
	status_dockers=$(docker ps -q | wc -l)/$(docker ps -aq | wc -l)
	status_packages=$(dpkg -l | grep ^ii -c)
	status_ifdata=$(vnstat -m --oneline | cut -f11 -d\;)
	{
		printf -- "---\\nlayout: page\\ntitle: Status\\ndescription: A (hopefully) recently generated server status page\\npermalink: /status/\\n---\\n\\n"
		printf "*Generated on %s*\\n\\n" "$status_timestamp"
		printf "* Uptime: %s" "$status_uptime"
		printf " Day%s\\n" "$(func_plural "$status_uptime")"
		printf "* CPU Load: %s\\n" "$status_cpuavgs"
		printf "* Users: %s\\n" "$status_users"
		printf "* RAM Usage: %s%%\\n" "$status_ram"
		printf "* Swap Usage: %s%%\\n" "$status_swap"
		printf "* Root Usage: %s\\n" "$status_rootuse"
		printf "* Downloads Usage: %s\\n" "$status_dluse"
		printf "* [Dockers](https://github.com/breadcat/Dockerfiles): %s\\n" "$status_dockers"
		printf "* Packages: %s\\n" "$status_packages"
		printf "* Monthly Data: %s\\n\\n" "$status_ifdata"
		printf "Hardware specifications themselves are covered on the [hardware page](/hardware/#server).\\n"
	} > "$status_filename"
	}
function func_dedupe_remote {
	dests=$(func_rclone_remote "$rclone_core" | wc -l)
	for i in $(seq 1 "$dests")
	do
		remote=$(func_rclone_remote "$rclone_core" | grep "$i")
		echo Deduplicating "$remote"
		$rclone_command dedupe --dedupe-mode newest "$remote" --log-file "$(func_dir_find config)/logs/rclone-dupe-$(date +%Y-%m-%d-%H%M).log"
	done
	}
function func_sync_remotes {
	source=$(func_rclone_remote "$rclone_core" | sed 1q)
	dests=$(func_rclone_remote "$rclone_core" | wc -l)
	for i in $(seq 2 "$dests")
	do
		dest=$(func_rclone_remote "$rclone_core" | grep "$i")
		echo Syncing "$source" to "$dest"
		$rclone_command sync "$source" "$dest" --verbose --log-file "$(func_dir_find config)/logs/rclone-sync-$(date +%Y-%m-%d-%H%M).log"
	done
	}
function func_update {
	func_check_running_as_root
	if [[ $distro =~ "Debian" ]]
	then
		func_update_debian
	elif [[ $distro =~ "Arch" ]]
	then
		func_update_arch
	else
		echo "Who knows what you're running"
	fi
	func_update_remaining
	}
function func_args {
	action=$1
	case "$action" in
		archive) func_backup_archive "$@" ;;
		beets) func_beets ;;
		borg) func_backup_borg ;;
		dedupe) func_dedupe_remote ;;
		docker) func_create_docker ;;
		duolingo) func_duolingo_streak ;;
		logger) func_logger ;;
		junk) func_junk_clean ;;
		magnet) func_magnet ;;
		payslip) func_payslip ;;
		permissions) func_permissions ;;
		rclone) func_rclone_mount ;;
		sort) func_media_sort ;;
		sshfs) func_sshfs_mount ;;
		status) func_status ;;
		sync) func_sync_remotes ;;
		update) func_update ;;
		*) echo "$0" && func_available_options ;;
	esac
	}
function main {
	export XZ_OPT=-e9
	distro=$(awk -F'"' '/^NAME/ {print $2}' /etc/os-release)
	username=$(grep home /etc/passwd -m1 | cut -f1 -d:)
	directory_home="/home/$username"
	directory_script="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
	rclone_command="rclone --config=$directory_script/rclone.conf"
	rclone_core="gdrive"
	docker_restart=("cbreader" "syncthing")
	func_args "$@"
	}

main "$@"
