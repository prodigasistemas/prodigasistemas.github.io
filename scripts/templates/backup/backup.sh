#!/bin/bash

_FOLDER="/var/tools-backup"

backup_database () {
  _DB_LIST=$(sed '/^ *$/d; /^ *#/d; /^database/!d' "$_HOST_FILE")
  _DB_TYPE_LIST=$(sed '/^ *$/d; /^ *#/d; /^database/!d' "$_HOST_FILE" | cut -d: -f2 | uniq)

  if [ -n "$_DB_LIST" ]; then
    for _database in $_DB_LIST; do
      _DB_TYPE=$(echo "$_database" | cut -d: -f2)
      _DB_HOST=$(echo "$_database" | cut -d: -f3)
      _DB_USER=$(echo "$_database" | cut -d: -f4)
      _DB_PASS=$(echo "$_database" | cut -d: -f5)
      _DATABASE_NAMES=$(echo "$_database" | cut -d: -f6)
      _DATABASE_NAMES=${_DATABASE_NAMES//,/ }

      for _DB_NAME in $_DATABASE_NAMES; do
        _SQL_FILE="$_DB_NAME-$(date +"%Y-%m-%d-%H-%M-%S").sql"
        _BACKUP_FILE="$_SQL_FILE.gz"
        _DEST="$_HOST_FOLDER/databases/$_DB_TYPE/$_DB_NAME"

        make_dir "$_DEST"

        write_log "Dumping $_DB_TYPE database $_DB_NAME"

        case $_DB_TYPE in
          mysql)
            _COMMAND=mysqldump
            _DB_DUMP="MYSQL_PWD=$_DB_PASS $_COMMAND -h $_DB_HOST -u $_DB_USER $_DB_NAME"
            ;;

          postgresql)
            _COMMAND=pg_dump
            _DB_DUMP="PGPASSWORD=$_DB_PASS $_COMMAND -h $_DB_HOST -U $_DB_USER -d $_DB_NAME"
            ;;
        esac

        perform_backup "$_COMMAND" "$_DEST" "$_DB_DUMP > /tmp/$_SQL_FILE && gzip -9 /tmp/$_SQL_FILE"
      done
    done
  fi
}

backup_folder () {
  _FOLDER_LIST=$(sed '/^ *$/d; /^ *#/d; /^folder/!d' "$_HOST_FILE")

  if [ -n "$_FOLDER_LIST" ]; then
    for _folder in $_FOLDER_LIST; do
      _name=$(echo "$_folder" | cut -d: -f2)
      _path=$(echo "$_folder" | cut -d: -f3)
      _exclude=$(echo "$_folder" | cut -d: -f4)

      [ -n "$_exclude" ] && _exclude=${_exclude//,/ }

      _BACKUP_FILE="$_name-$(date +"%Y-%m-%d-%H-%M-%S").tar.gz"
      _DEST="$_HOST_FOLDER/folders/$_name"

      make_dir "$_DEST"

      if [ -n "$_exclude" ]; then
        for _pattern in $_exclude; do
          _EXCLUDE="--exclude=$_pattern "
        done
      fi

      write_log "Compressing $_BACKUP_FILE"

      perform_backup "tar" "$_DEST" "tar czf /tmp/$_BACKUP_FILE $_path --exclude-vcs $_EXCLUDE"
    done
  fi
}

perform_backup () {
  _command_name=$1
  _destination=$2
  _command_line=$3
  _access="$_HOST_USER@$_HOST_ADDRESS"

  if [ "$_HOST_ADDRESS" = "local" ]; then
    if [ -z "$(command -v $_command_name)" ]; then
      write_log "$_command_name is not installed!"
    else
      eval $_command_line >> $_LOG_FILE 2>> $_LOG_FILE

      [ $? -eq 0 ] && [ -e "/tmp/$_BACKUP_FILE" ] && mv "/tmp/$_BACKUP_FILE" "$_destination"
    fi
  else
    _check_command=$(ssh -C -E "$_LOG_FILE" -p "$_HOST_PORT" "$_access" "command -v $_command_name")

    if [ -z "$_check_command" ]; then
      write_log "$_command_name is not installed!"
    else
      ssh -C -p "$_HOST_PORT" "$_access" "$_command_line" >> "$_LOG_FILE" 2>> "$_LOG_FILE"

      if [ $? -eq 0 ]; then
        scp -C -P "$_HOST_PORT" "$_access:/tmp/$_BACKUP_FILE" "$_destination" >> "$_LOG_FILE" 2>> "$_LOG_FILE"

        ssh -C -p "$_HOST_PORT" "$_access" "rm /tmp/$_BACKUP_FILE" >> "$_LOG_FILE" 2>> "$_LOG_FILE"
      fi
    fi
  fi

  remove_old_files "$_destination"
}

remove_old_files () {
  _DIR=$1

  [ -z "$_MAX_FILES" ] && _MAX_FILES=7

  cd "$_DIR"

  _NUMBER_FILES=$(ls 2> /dev/null | wc -l)

  if [ "$_NUMBER_FILES" -gt "$_MAX_FILES" ]; then
    let _NUMBER_REMOVALS=$_NUMBER_FILES-$_MAX_FILES

    _FILES_REMOVE=$(ls | head -n "$_NUMBER_REMOVALS")

    for _FILE in $_FILES_REMOVE; do
      write_log "Removing old file $_FILE"
      rm -f "$_FILE"
    done
  fi
}

to_sync () {
  _LOG_SYNC="$_FOLDER/logs/synchronizing.log"

  if [ -n "$_RSYNC_HOST" ]; then
    if [ -z "$(command -v rsync)" ]; then
      write_sync_log "rsync is not installed!"
    else
      write_sync_log "------------------------------------------------------------------------------------------"
      write_sync_log "Synchronizing $_FOLDER with $_RSYNC_HOST"

      rsync -CzpOur --delete --log-file="$_LOG_SYNC" "$_FOLDER" "$_RSYNC_HOST" >> /dev/null 2>> "$_LOG_SYNC"
    fi
  fi

  if [ -n "$_AWS_BUCKET" ]; then
    if [ -z "$(command -v aws)" ]; then
      write_log "awscli is not installed!"
    else
      write_sync_log "------------------------------------------------------------------------------------------"
      write_sync_log "Synchronizing $_FOLDER with s3://$_AWS_BUCKET/"

      aws s3 sync $_FOLDER "s3://$_AWS_BUCKET/" --delete >> "$_LOG_SYNC" 2>> "$_LOG_SYNC"
    fi
  fi
}

write_log () {
  _MESSAGE=$1

  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $_MESSAGE" >> "$_LOG_FILE"
}

write_sync_log () {
  _MESSAGE=$1

  echo "$(date +"%Y/%m/%d %H:%M:%S") $_MESSAGE" >> "$_LOG_SYNC"
}

make_dir () {
  _dir=$1
  [ ! -e "$_dir" ] && mkdir -p "$_dir"
}

main () {
  [ -e "$_FOLDER/backup.conf" ] && source "$_FOLDER/backup.conf"

  _HOSTS_FILE="$_FOLDER/hosts.list"

  make_dir "$_FOLDER/logs"

  if [ -e "$_HOSTS_FILE" ]; then
    _HOSTS_LIST=$(sed '/^ *$/d; /^ *#/d;' $_HOSTS_FILE)

    if [ -n "$_HOSTS_LIST" ]; then
      for _host in $_HOSTS_LIST; do
        _HOST_NAME=$(echo "$_host" | cut -d: -f1)
        _HOST_ADDRESS=$(echo "$_host" | cut -d: -f2)
        _HOST_PORT=$(echo "$_host" | cut -d: -f3)
        _HOST_USER=$(echo "$_host" | cut -d: -f4)
        _HOST_FILE="$_FOLDER/hosts/$_HOST_NAME.list"
        _HOST_FOLDER="$_FOLDER/storage/$_HOST_NAME"
        _LOG_FILE="$_FOLDER/logs/$_HOST_NAME.log"

        backup_database

        backup_folder
      done
    fi

    to_sync
  fi
}

main