#!/bin/bash

# functions
function find_directory {
	find "$directory_home" -maxdepth 3 -mount -type d -name "$1" 2>/dev/null
}
function find_remote {
	rclone listremotes | awk -v remote="$1" '$0 ~ remote {print $0;exit}'
}
function check_root {
	if [ "$EUID" -ne 0 ]; then
		echo "Please run as root"
		exit 0
	fi
}
function check_not_root {
	if [ "$EUID" -eq 0 ]; then
		echo "Don't run this function as root"
		exit 0
	fi
}
function check_depends {
	dependencies=(aria2c awk bash docker docker-compose ffmpeg getmail git gnuplot journalctl logname media-sort mp3val mpack munpack opustags phockup pip3 python3 qpdf rbw rclone sed seq sort svgo uniq vnstat we-get yt-dlp)
	echo "Checking dependencies..."
	for i in "${dependencies[@]}"; do
		echo -n "$i: "
		if [[ $(command -v "$i") ]]; then
			echo -e "\e[32mpresent\e[39m"
		else
			echo -e "\e[31mmissing\e[39m"
		fi
	done
	exit 1
}
function umount_remote {
	if [ -z "$2" ]; then
		working_directory="$(find_directory "$1")"
	else
		working_directory="$(find_directory "$2")"
	fi
	umount "$working_directory"
	fusermount -uz "$working_directory" 2>/dev/null
	find "$working_directory" -maxdepth 1 -mount -type d -not -path "*/\.*" -empty -delete
}
function password_manager {
	case "$1" in
	addr) check_not_root && rbw get --full "$2" | awk '/URI:/ {print $2}' ;;
	full) check_not_root && rbw get --full "$2" ;;
	pass) check_not_root && rbw get "$2" ;;
	sync) check_not_root && rbw sync ;;
	user) check_not_root && rbw get --full "$2" | awk '/Username:/ {print $2}' ;;
	*) check_not_root && rbw get "$2" ;;
	esac
}
function duolingo_streak {
	# check api is installed
	[[ -d "$(find_directory config)/duolingo" ]] || git clone https://github.com/KartikTalwar/Duolingo.git "$(find_directory config)/duolingo"
	# cd to git dir to include module
	cd "$(find_directory config)/duolingo" || return
	# write script
	password_manager sync
	{
		printf "#!/usr/bin/env python3\\n\\n"
		printf "import duolingo\\n"
		printf "lingo  = duolingo.Duolingo('%s', password='%s')\\n" "$(password_manager user duolingo)" "$(password_manager pass duolingo)"
		printf "lingo.buy_streak_freeze()"
	} >"streak-freeze.py"
	# run and remove script
	python "streak-freeze.py"
	rm "streak-freeze.py"
}
function blog_duolingo_rank {
	duo_username="$(awk -F'[/()]' '/Duolingo/ {print $5}' "$(find_directory blog."$domain")"/content/about.md)"
	rank_filename="$(find_directory blog."$domain")/content/posts/logging-duolingo-ranks-over-time.md"
	echo -n "Fetching data for $duo_username... "
	page_source="$(curl -s https://duome.eu/"$duo_username")"
	rank_lingot="$(printf %s "$page_source" | awk -F"[#><]" '/icon lingot/ {print $15}')"
	rank_streak="$(printf %s "$page_source" | awk -F"[#><]" '/icon streak/{getline;print $15}')'"
	echo -e "$i \e[32mdone\e[39m"
	echo -n "Appending ranks to page... "
	echo "| $(date +%F) | $(date +%H:%M) | $rank_streak | $rank_lingot |" | tr -d \' >>"$rank_filename"
	echo -e "$i \e[32mdone\e[39m"
	echo -n "Amending lastmod value... "
	mod_timestamp="$(date +%FT%H:%M:00)"
	sed -i "s/lastmod: .*/lastmod: $mod_timestamp/g" "$rank_filename"
	echo -e "$i \e[32mdone\e[39m"
}
function docker_build {
	cd "$directory_script" || exit
	# write env file, overwriting any existing
	password_manager sync
	{
		printf "DOMAIN=%s\\n" "$domain"
		printf "PUID=%s\\n" "$(id -u)"
		printf "PGID=%s\\n" "$(id -g)"
		printf "TZ=%s\\n" "$(cat /etc/timezone)"
		printf "DOCKDIR=%s\\n" "$(find_directory docker)"
		printf "SYNCDIR=%s\\n" "$(find_directory vault)"
		printf "RCLONE_REMOTE_MEDIA=%s\\n" "$(find_remote media)"
		printf "WG_WEBUI_PASS=%s\\n" "$(password_manager pass 'wireguard admin')"
		printf "WG_PRIVKEY=%s\\n" "$(password_manager pass 'wireguard private key')"
		printf "DBPASSWORD=%s\\n" "$(password_manager pass postgresql)"
	} >"$directory_script/.env"
	# make network, if not existing
	if ! printf "%s" "$(docker network ls)" | grep -q "proxy"; then
		echo Creating docker network
		docker network create proxy
	fi
	# start containers
	echo Starting docker containers
	docker-compose up -d --remove-orphans
	# rewrite htpasswd
	printf "%s%s" "$(password_manager user 'htpasswd')" "$(htpasswd -bnBC 10 "" "$(password_manager pass 'htpasswd')")" >"$(find_directory config)/traefik/htpasswd"
	# delete temporary env file
	if [[ -f "$directory_script/.env" ]]; then
		echo Deleting detected env file
		rm "$directory_script/.env"
	fi
	# clean up existing stuff
	echo Cleaning up existing docker files
	for i in volume image system network; do
		docker "$i" prune -f
	done
	docker system prune -af
}
function media_logger {
	# specify directories
	git_directory="$(find_directory logger)"
	file_git_log="$git_directory/media.log"
	log_remote="$(find_remote media)"
	git_logger="git --git-dir=$git_directory/.git --work-tree=$git_directory"
	# git configuruation
	if [ ! -e "$git_directory" ]; then
		printf "Logger directory not found, quitting...\n"
		exit 1
	fi
	if [ ! -e "$git_directory/.git" ]; then
		printf "Initialising blank git repo...\n"
		$git_logger init
	fi
	if [ -e "$file_git_log.xz" ]; then
		printf "Decompressing existing xz archive...\n"
		xz -d "$file_git_log.xz"
	fi
	if [ -e "$file_git_log" ]; then
		printf "Removing existing log file...\n"
		rm "$file_git_log"
	fi
	printf "Creating log...\n"
	rclone ls "$log_remote" | sort -k2 >"$file_git_log"
	printf "Appending size information...\n"
	rclone size "$log_remote" >>"$file_git_log"
	printf "Commiting log file to repository...\n"
	$git_logger add "$file_git_log"
	$git_logger commit -m "Update: $(date +%F)"
	if [ -e "$file_git_log.xz" ]; then
		printf "Removing xz archive...\n"
		rm "$file_git_log.xz"
	fi
	printf "Compressing log file...\n"
	xz "$file_git_log"
	printf "Compressing repository...\n"
	$git_logger config pack.windowMemory 10m
	$git_logger config pack.packSizeLimit 20m
	$git_logger gc --aggressive --prune
	printf "Log complete!"
}
function parse_magnets {
	# sources and destinations
	cd "$(find_directory vault)" || exit
	rclone_remote="raw-seedbox:watch/"
	# check for aria
	if [ ! -x "$(command -v aria2c)" ]; then # not installed
		echo "Aria doesn't seem to be installed. Exiting" && exit
	fi
	# trackers
	trackers_list=(
		"udp://9.rarbg.to:2710/announce"
		"udp://denis.stalker.upeer.me:6969/announce"
		"udp://exodus.desync.com:6969/announce"
		"udp://ipv6.tracker.harry.lu:80/announce"
		"udp://open.demonii.si:1337/announce"
		"udp://open.stealth.si:80/announce"
		"udp://p4p.arenabg.com:1337/announce"
		"udp://retracker.lanta-net.ru:2710/announce"
		"udp://tracker.coppersurfer.tk:6969/announce"
		"udp://tracker.cyberia.is:6969/announce"
		"udp://tracker.leechers-paradise.org:6969/announce"
		"udp://tracker.open-internet.nl:6969/announce"
		"udp://tracker.opentrackr.org:1337/announce"
		"udp://tracker.pirateparty.gr:6969/announce"
		"udp://tracker.tiny-vps.com:6969/announce"
		"udp://tracker.torrent.eu.org:451/announce"
	)
	for i in "${trackers_list[@]}"; do
		trackers="$i,$trackers"
	done
	# magnet loop
	for j in *.magnet; do
		[ -f "$j" ] || break
		timeout 3m aria2c --bt-tracker="$trackers" --bt-metadata-only=true --bt-save-metadata=true "$(cat "$j")" && rm "$j"
	done
	# torrent loop, move to watch
	for k in *.torrent; do
		[ -f "$k" ] || break
		for i in *.torrent; do rclone move "$k" "$rclone_remote"; done
	done
}
function parse_payslips {
	# temporary directories
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
	} >getmailrc
	getmail --getmaildir "$directory_temp"
	cd new || exit
	grep "$(password_manager user payslip)" ./* | cut -f1 -d: | uniq | xargs munpack -f
	# decrypt payslip file
	for i in *.PDF; do
		fileProtected=0
		qpdf "$i" --check || fileProtected=1
		if [ $fileProtected == 1 ]; then
			parsed_name="$(printf "%s" "$i" | awk -FX '{print substr($3,5,4) "-" substr($3,3,2) "-" substr($3,1,2) ".pdf"}')"
			qpdf --password="$(password_manager pass payslip)" --decrypt "$i" "$parsed_name" && rm "$i"
			rclone move "$parsed_name" "$(find_remote paperwork)/personal/workplace/wages/"
		fi
	done
	# clean up afterwards
	rm -r "$directory_temp"
}
function sort_media {
	# check mounts
	mounts="seedbox media"
	for i in $mounts; do
		mount_remote mount "$i"
	done
	# main sorting process
	dir_import=$(find_directory seedbox)/
	if [[ -d "$dir_import" ]]; then
		dir_tv=$(find_directory media)/videos/television
		dir_mov=$(find_directory media)/videos/movies
		temp_tv="{{ .Name }}/{{ .Name }} S{{ printf \"%02d\" .Season }}E{{ printf \"%02d\" .Episode }}{{ if ne .ExtraEpisode -1 }}-{{ printf \"%02d\" .ExtraEpisode }}{{end}}.{{ .Ext }}"
		temp_mov="{{ .Name }} ({{ .Year }})/{{ .Name }}.{{ .Ext }}"
		media-sort --action copy --concurrency 1 --accuracy-threshold 90 --tv-dir "$dir_tv" --movie-dir "$dir_mov" --tv-template "$temp_tv" --movie-template "$temp_mov" --recursive --overwrite-if-larger "$dir_import"
	else
		printf "Import directory not found.\\n"
		exit 0
	fi
	for i in $mounts; do
		umount_remote "$i"
	done
}
function mount_remote {
	# check allow_other in fuse.conf
	if ! grep -q "^user_allow_other$" /etc/fuse.conf; then
		check_root
		printf "user_allow_other not found in fuse.conf.\\nAppending to file. Please restart the script.\\n"
		echo "user_allow_other" >>/etc/fuse.conf
		exit 0
	fi
	if [ -n "$2" ]; then
		printf "Mounting specified remote...\\n"
		rclone_mount_process "$2"
	else
		printf "Mounting all remotes...\\n"
		rclone_array="$(rclone listremotes | awk -F '[-:]' '/^drive/ && !/backups/ && !/saves/ {print $2}' | xargs)"
		for i in $rclone_array; do
			rclone_mount_process "$i"
		done
	fi
}
function rclone_mount_process {
	remote="$(find_remote "$1")"
	mount_point="$directory_home/$1"
	mkdir -p "$mount_point"
	if [[ -f "$mount_point/.mountcheck" || -n "$(find "$mount_point" -maxdepth 1 -mindepth 1 | head -n 1)" ]]; then
		printf "%s already mounted.\\n" "$1"
	else
		printf "%s not mounted.\\n" "$1"
		printf "Re-mounting... "
		fusermount -uz "$mount_point" 2>/dev/null && sleep 3
		rclone mount "$remote" "$mount_point" --allow-other --daemon --log-file "$(find_directory config)/logs/rclone-$1.log"
		printf "done\\n"
	fi
}
function blog_status {
	status_uptime=$(($(cut -f1 -d. </proc/uptime) / 86400))
	{
		printf -- "---\\ntitle: Status\\nlayout: single\\n---\\n\\n"
		printf "*Generated on %(%Y-%m-%d at %H:%M)T*\\n\\n" -1
		printf "* Uptime: %s Day%s\\n" "$status_uptime" "$(if (("$status_uptime" > 1)); then echo s; fi)"
		printf "* CPU Load: %s\\n" "$(cut -d" " -f1-3 </proc/loadavg)"
		printf "* Users: %s\\n" "$(uptime | grep -oP '.{3}user' | sed 's/\user//g' | xargs)"
		printf "* RAM Usage: %s%%\\n" "$(printf "%.0f" "$(free | awk '/Mem/ {print $3/$2 * 100.0}')")"
		printf "* Swap Usage: %s%%\\n" "$(printf "%.0f" "$(free | awk '/Swap/ {print $3/$2 * 100.0}')")"
		printf "* Root Usage: %s\\n" "$(df / | awk 'END{print $5}')"
		printf "* Cloud Usage: %s\\n" "$(git --git-dir="$(find_directory logger)/.git" show | awk 'END{print $3" "$4}')"
		printf "* [Dockers](https://github.com/breadcat/Dockerfiles): %s\\n" "$(docker ps -q | wc -l)/$(docker ps -aq | wc -l)"
		printf "* Packages: %s\\n" "$(dpkg -l | grep ^ii -c)"
		printf "* Monthly Data: %s\\n\\n" "$(vnstat -m --oneline | cut -f11 -d\;)"
		printf "Hardware specifications themselves are covered on the [hardware page](/hardware/#server).\\n"
	} >"$(find_directory blog."$domain")/content/status.md"
}
function blog_weight {
	if [ "$2" = "date" ]; then
		printf "Writing empty dates... "
		weight_filename="$(find_directory blog."$domain")/content/weight.md"
		page_source="$(head -n -1 "$weight_filename")"
		previous_date="$(printf %s "$page_source" | awk -F, 'END{print $1}')"
		sequence_count="$((($(date --date="$(date +%F)" +%s) - $(date --date="$previous_date" +%s)) / (60 * 60 * 24)))"
		{
			printf "%s\\n" "$page_source"
			printf "%s" "$(for i in $(seq $sequence_count); do printf "%s,\\n" "$(date -d "$previous_date+$i day" +%F)"; done)"
			printf "\\n</pre></details>"
		} >"$weight_filename"
		printf "done\\n"
		exit 0
	fi
	printf "Drawing graph... "
	weight_filename="$(find_directory blog."$domain")/content/weight.md"
	weight_rawdata="$(awk '/<pre>/{flag=1; next} /<\/pre>/{flag=0} flag' "$weight_filename" | sort -u)"
	weight_dateinit="$(awk '/date:/ {print $2}' "$weight_filename")"
	grep "^$(date +%Y)-" <<<"$weight_rawdata" >temp.dat
	gnuplot <<-EOF
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
	printf "done\\nWriting page... "
	{
		printf -- "---\\ntitle: Weight\\nlayout: single\\ndate: %s\\nlastmod: %(%Y-%m-%dT%H:%M:00)T\\n---\\n\\n" "$weight_dateinit" -1
		printf "%s\\n\\n" "$(svgo -i "temp.svg" --multipass -o - -q -p 0)"
		printf "<details><summary>Raw data</summary>\\n<pre>\\n%s\\n</pre></details>" "$weight_rawdata"

	} >"$weight_filename"
	printf "done\\nCleaning up... "
	rm temp.{dat,svg}
	printf "done\\n"
}
function remotes_dedupe {
	dests=$(rclone listremotes | grep "gdrive" -c)
	for i in $(seq "$dests"); do
		remote=$(rclone listremotes | grep "gdrive.*$i")
		echo Deduplicating "$remote"
		rclone dedupe --dedupe-mode newest "$remote" --log-file "$(find_directory config)/logs/rclone-dupe-$(date +%F-%H%M).log"
	done
}
function remotes_tokens {
	echo "Refreshing rclone remote tokens"
	for i in $(rclone listremotes | awk -v remote="$backup_prefix" '$0 ~ remote {print $0}'); do
		if rclone lsd "$i" &>/dev/null; then
			echo -e "$i \e[32msuccess\e[39m"
		else
			echo -e "$i \e[31mfailed\e[39m"
		fi
	done
}
function remotes_sync {
	source=$(find_remote "gdrive")
	dests=$(rclone listremotes | grep "gdrive" -c)
	for i in $(seq 2 "$dests"); do
		dest=$(rclone listremotes | grep "gdrive.*$i")
		if rclone lsd "$dest" &>/dev/null; then
			if [ -n "$2" ]; then
				directory="$2"
				printf "Syncing %s directory to %s...\\n" "$directory" "$dest"
				rclone sync "$source/$directory" "$dest/$directory" --drive-server-side-across-configs --drive-stop-on-upload-limit --verbose --log-file "$(find_directory config)/logs/rclone-sync-$directory-$(date +%F-%H%M).log"
			else
				printf "Syncing %s to %s...\\n" "$source" "$dest"
				rclone sync "$source" "$dest" --drive-server-side-across-configs --drive-stop-on-upload-limit --verbose --log-file "$(find_directory config)/logs/rclone-sync-$(date +%F-%H%M).log"
			fi
		fi
	done
}
function parse_photos {
	source=$(find_directory DCIM)
	mount="pictures"
	mount_remote mount "$mount"
	destination=$(find_directory $mount)
	# main sorting process
	if [[ -d "$destination" ]]; then
		phockup "$source" "$destination/personal/photos/" -m
		find "$source" -maxdepth 3 -mount -type d -not -path "*/\.*" -empty -delete
	else
		printf "Import directory not found.\\n"
		exit 0
	fi
	umount_remote "$mount"
}
function backup_docker {
	check_not_root
	password_manager sync
	password="$(password_manager pass 'backup archive password')"
	backup_final="$(find_remote backups)"
	cd "$(find_directory config)" || exit
	for i in */; do
		backup_file="$(basename "$i")_backup-$(date +%F-%H%M).tar.xz.gpg"
		echo -n Backing up "$i"...
		if docker ps -a | grep -q "$i"; then
			docker stop "$i" 1>/dev/null
			sudo tar -cJf - "$i" | gpg -c --batch --passphrase "$password" >"$backup_file"
			docker start "$i" 1>/dev/null
		else
			sudo tar -cJf - "$i" | gpg -c --batch --passphrase "$password" >"$backup_file"
		fi
		sudo chown "$username":"$username" "$backup_file"
		echo -e "$i \e[32mdone\e[39m"
	done
	# send to remotes, final operation is a move, removing the backup
	for i in *_backup-*."tar.xz.gpg"; do
		for j in $(rclone listremotes | awk -v remote="$backup_prefix" '$0 ~ remote {print $0}'); do
			echo -n Copying "$i" to "$j"...
			rclone copy "$i" "$j" && echo -e "\e[32mdone\e[39m" || echo -e "\e[31mfailed\e[39m"
		done
		echo -n Moving "$i" to "$backup_final"...
		rclone move "$i" "$backup_final" && echo -e "\e[32mdone\e[39m" || echo -e "\e[31mfailed\e[39m"
	done
}
function clean_space {
	space_initial="$(df / | awk 'FNR==2{ print $4}')"
	log_file="$(find_directory config)/logs/clean-$(date +%F-%H%M).log"
	check_root
	# journals
	journalctl --vacuum-size=75M >>"$log_file"
	# docker
	for i in volume image; do
		docker "$i" prune -f >>"$log_file"
	done
	# apt
	apt-get clean >>"$log_file"
	# temp directory
	rm -rf /tmp/tmp.* >>"$log_file"
	space_after="$(df / | awk 'FNR==2{ print $4}')"
	printf "Bytes freed: %s\\n" "$(("$space_after" - "$space_initial"))"
}
function remote_sizes {
	dests=$(rclone listremotes | grep "gdrive" -c)
	for i in $(seq "$dests"); do
		remote=$(rclone listremotes | grep "gdrive.*$i")
		echo -n Calculating "$remote"...
		rclone size "$remote" | xargs
	done
}
function system_update {
	check_root
	if [[ $distro =~ "Debian" ]]; then
		# Update Debian
		export DEBIAN_FRONTEND=noninteractive
		apt-get update
		apt-get dist-upgrade -y
		apt-get autoremove --purge -y
		apt-get clean
		if [ -x "$(command -v yt-dlp)" ]; then
			yt-dlp -U
		fi
		if [ -x "$(command -v rclone)" ]; then
			curl --silent "https://rclone.org/install.sh" | bash
		fi
	elif [[ $distro =~ "Arch" ]]; then
		# Update Archlinux
		if [ -x "$(command -v paru)" ]; then
			paru -Syu --noconfirm
		else
			pacman -Syu --noconfirm
		fi
	else
		echo "Who knows what you're running"
	fi
	# Update remaining applications
	find "$(find_directory config)" -maxdepth 2 -name ".git" -type d | sed 's/\/.git//' | xargs -P10 -I{} git -C {} pull
	if [ -x "$(command -v we-get)" ]; then
		echo "Updating we-get..."
		pip3 install --upgrade git+https://github.com/rachmadaniHaryono/we-get
	fi
	if [ -x "$(command -v media-sort)" ]; then
		echo "Updating media-sort..."
		cd "/usr/local/bin" || return
		curl https://i.jpillora.com/media-sort | bash
	fi
}
function main {
	distro="$(awk -F'"' '/^NAME/ {print $2}' /etc/os-release)"
	username="$(logname)"
	directory_home="/home/$username"
	backup_prefix="backup-"
	domain="$(awk -F'"' '/domain/ {print $2}' "$(find_directory traefik)/traefik.toml")"
	directory_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
	case "$1" in
	backup) backup_docker ;;
	bookmarks) grep -P "\t\t\t\<li\>" "$(find_directory startpage)/index.html" | sort -t\> -k3 >"$(find_directory startpage)/bookmarks.txt" ;;
	clean) clean_space ;;
	dedupe) remotes_dedupe ;;
	depends) check_depends ;;
	docker) docker_build ;;
	logger) media_logger ;;
	magnet) parse_magnets ;;
	mount) mount_remote "$@" ;;
	payslip) parse_payslips ;;
	permissions) check_root && chown "$username":"$username" "$directory_script/rclone.conf" ;;
	photos) parse_photos ;;
	rank) blog_duolingo_rank ;;
	refresh) remotes_tokens ;;
	size) remote_sizes ;;
	sort) sort_media ;;
	status) blog_status ;;
	streak) duolingo_streak ;;
	sync) remotes_sync "$@" ;;
	umount) umount_remote "$@" ;;
	update) system_update ;;
	weight) blog_weight "$@" ;;
	*) echo "$0" && awk '/^function main/,EOF' "$0" | awk '/case/{flag=1;next}/esac/{flag=0}flag' | awk -F"\t|)" '{print $2}' | tr -d "*" | sort | xargs ;;
	esac
}

main "$@"
