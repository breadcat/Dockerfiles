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
	printf "SAVEDIR=%s\\n" "$(func_dir_find saves)"
	printf "SYNCDIR=%s\\n" "$(func_dir_find vault)"
	printf "WORKDIR=%s\\n" "$(func_dir_find paperwork)"
	printf "RCLONE_REMOTE_MEDIA=%s\\n" "$(func_rclone_remote media)"
	printf "RCLONE_REMOTE_SAVES=%s\\n" "$(func_rclone_remote saves)"
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
			qpdf --password="$payslip_encryption" --decrypt "$i" "decrypt-$i" && rm "$i"
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
function func_archive {
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
			tar -cJf "backup-$i-$(date +%Y-%m-%d-%H%M).tar.xz" --ignore-failed-read "$HOME/$i"
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
		pip3 install --upgrade git+https://github.com/rachmadaniHaryono/we-get
	fi
	if [ -x "$(command -v plowmod)" ]
	then
		su -c "plowmod -u" -s /bin/sh "$username"
		chown -R "$username":"$username" "$directory_home/.config/plowshare"
	fi
	}
function func_borg {
	# https://opensource.com/article/17/10/backing-your-machines-borg
	working_directory=$(func_dir_find backups)/borg
	echo "$working_directory"
	}
function func_create_docker {
	cd "$directory_script" || exit
	func_docker_env_delete
#	delete_docker_compose
	func_include_credentials
	# update submodules
	git pull --recurse-submodules
	# write compose file
#	{
#	printf "nope"
#	} > docker-compose.yml
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
	if ! printf "$(docker network ls)" | grep -q "proxy"
	then
		echo Creating docker network
		docker network create proxy
	fi
	# start containers
	echo Starting docker containers
	docker-compose up -d --remove-orphans
	func_docker_env_delete
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
	for i in *.magnet
	do
		echo Parsing magnet files
		magnet_source="$(cat "$i")"
		python "$mag2tor_script_path" -m "$magnet_source" -o "$(func_dir_find downloads)/remote/watch/"
		rm "$i"
	done
	for i in *.torrent
	do
		echo Moving torrent files
		mv "*.torrent" "$(func_dir_find downloads)/remote/watch/"
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
	grep "$payslip_sender" * | cut -f1 -d: | uniq | xargs munpack -f
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
	for i in backups media paperwork pictures saves
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
			$rclone_command mount "drive-$i": "/home/peter/$i" --vfs-cache-mode minimal --allow-other --allow-non-empty --daemon --log-file "$(func_dir_find config)/logs/rclone-$i.log"
			echo restarting docker containers
			for j in "${docker_restart[@]}"
			do
				docker restart "$j"
			done
		fi
	done
	}

function func_sshfs_mount {
	func_include_credentials
	echo sshfs mount checker
	seedbox_host="$seedbox_username.seedbox.io"
	seedbox_mount="$(func_dir_find downloads)/remote"
	if [[ -d "$seedbox_mount/files" ]]
	then
		echo "sshfs mount exists"
	else
		echo "sshfs mount missing, mounting"
		fusermount -uz "$seedbox_mount"
		printf "%s" "$seedbox_password" | sshfs "$seedbox_username@$seedbox_host":/ "$seedbox_mount" -o password_stdin -o allow_other
	fi
	}

function func_status {
	status_filename=$(func_dir_find blog)/status.md
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
	status_ifdata=$(vnstat -i eth0 -m --oneline | cut -f11 -d\;)
	{
		printf -- "---\\nlayout: page\\ntitle: Server Status\\ndescription: A (hopefully) recently generated server status page\\npermalink: /status/\\n---\\n\\n"
		printf "*Generated on %s*\\n\\n" "$status_timestamp"
		printf "* Uptime: %s" "$status_uptime"
		printf " Day%s\\n" "$(plural "$status_uptime")"
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
function func_sync_remotes {
	source=$(func_rclone_remote gdrive | sed 1q)
	dest=$(func_rclone_remote gdrive | sed -n 2p)
	echo Syncing "$source" to "$dest"
	$rclone_command sync "$source" "$dest" --drive-server-side-across-configs --verbose --log-file "$(func_dir_find config)/logs/rclone-sync-$(date +%Y-%m-%d-%H%M).log"
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
		archive) func_archive "$@" ;;
		borg) func_borg ;;
		docker) func_create_docker ;;
		logger) func_logger ;;
		magnet) func_magnet ;;
		payslip) func_payslip ;;
		permissions) func_permissions ;;
		rclone) func_rclone_mount ;;
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
	username=$(grep home /etc/passwd | sed 1q | cut -f1 -d:)
	directory_home="/home/$username"
	directory_script="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
	rclone_command="rclone --config=$directory_script/rclone.conf"
	docker_restart=("flexget" "cbreader" "syncthing")
	func_args "$@"
	}

main "$@"
