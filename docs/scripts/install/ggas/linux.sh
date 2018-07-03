#!/bin/bash

# http://www.orafaq.com/wiki/NLS_LANG

export _APP_NAME="GGAS"
_DEFAULT_PATH="/opt"
_GRADLE_VERSION="2.2.1"
_OPTIONS_LIST="install_ggas 'Install GGAS' \
               import_ggas_database 'Import GGAS Database' \
               configure_nginx 'Configure host on NGINX'"

setup () {
  [ -z "$_CENTRAL_URL_TOOLS" ] && _CENTRAL_URL_TOOLS="https://prodigasistemas.github.io/ti"

  ping -c 1 "$(echo $_CENTRAL_URL_TOOLS | sed 's|http.*://||g; s|/ti||g;' | cut -d: -f1)" > /dev/null
  [ $? -ne 0 ] && echo "$_CENTRAL_URL_TOOLS connection was not successful!" && exit 1

  _FUNCTIONS_FILE="/tmp/.tools.installer.functions.linux.sh"

  curl -sS $_CENTRAL_URL_TOOLS/scripts/functions/linux.sh > $_FUNCTIONS_FILE 2> /dev/null
  [ $? -ne 0 ] && echo "Functions were not loaded!" && exit 1

  [ -e "$_FUNCTIONS_FILE" ] && source $_FUNCTIONS_FILE && rm $_FUNCTIONS_FILE

  os_check
}

install_ggas () {
  _CURRENT_DIR=$(pwd)

  java_check 7

  [ ! -e "$_DEFAULT_PATH/wildfly" ] && message "Error" "Wildfly is not installed!"

  confirm "Confirm the installation of $_APP_NAME?"
  [ $? -eq 1 ] && main

  tool_check git
  tool_check wget
  tool_check unzip

  cd $_DEFAULT_PATH

  delete_file "$_DEFAULT_PATH/ggas"

  print_colorful yellow bold "> Cloning repo from http://ggas.com.br/root/ggas.git..."

  git clone http://ggas.com.br/root/ggas.git

  [ $? -ne 0 ] && message "Error" "Download of $_APP_NAME not realized!"

  chown "$_USER_LOGGED":"$_USER_LOGGED" -R "$_DEFAULT_PATH/ggas"

  print_colorful yellow bold "> Installing Gradle $_GRADLE_VERSION..."

  cd $_DEFAULT_PATH

  wget https://services.gradle.org/distributions/gradle-$_GRADLE_VERSION-bin.zip

  [ $? -ne 0 ] && message "Error" "Download of Gradle $_GRADLE_VERSION not realized!"

  unzip -oq gradle-$_GRADLE_VERSION-bin.zip

  rm gradle-$_GRADLE_VERSION-bin.zip

  ln -sf gradle-$_GRADLE_VERSION $_DEFAULT_PATH/gradle

  print_colorful yellow bold "> Building $_APP_NAME..."

  cd $_DEFAULT_PATH/ggas

  run_as_user "$_USER_LOGGED" "JAVA_HOME=$(get_java_home 7) $_DEFAULT_PATH/gradle/bin/gradle build"

  print_colorful yellow bold "> Deploying $_APP_NAME..."

  /etc/init.d/wildfly stop

  run_as_user "$_USER_LOGGED" "cp $_DEFAULT_PATH/ggas/workspace/build/libs/workspace*.war $_DEFAULT_PATH/wildfly/standalone/deployments/ggas.war"

  /etc/init.d/wildfly start

  cd "$_CURRENT_DIR"

  [ $? -eq 0 ] && message "Notice" "$_APP_NAME successfully installed!"
}

get_section () {
  version=$1
  order=$2

  section=$(echo $version | cut -d. -f$order)

  [ "${#section}" == "1" ] && section="0$section"

  echo $section
}

zero_fill () {
  version=$1
  major=$(get_section $version 1)
  minor=$(get_section $version 2)
  patch=$(get_section $version 3)

  echo "$major.$minor.$patch"
}

rename_versions () {
  for i in $(ls sql/GGAS_Ver*.sql)
  do
    file=$i
    version=$(echo $file | cut -d- -f2 | cut -d_ -f1)
    replace=$(zero_fill $version)
    new_name=$(echo $file | sed "s/$version/$replace/")
    mv $file $new_name
  done
}

import_ggas_database () {
  _CURRENT_DIR=$(pwd)

  tool_check dos2unix

  if [ -e "$_ORACLE_CONFIG" ]; then
    _SSH_PORT=$(search_value ssh.port "$_ORACLE_CONFIG")
  else
    _SSH_PORT=2222
  fi

  ssh -p $_SSH_PORT root@localhost

  [ $? -ne 0 ] && message "Error" "ssh: connect to host localhost port $_SSH_PORT: Connection refused"

  confirm "Confirm import $_APP_NAME database?"
  [ $? -eq 1 ] && main

  if [ ! -e "$_DEFAULT_PATH/ggas" ]; then
    cd $_DEFAULT_PATH
    tool_check git

    print_colorful yellow bold "> Cloning repo from http://ggas.com.br/root/ggas.git..."

    git clone http://ggas.com.br/root/ggas.git
    [ $? -ne 0 ] && message "Error" "Download of GGAS not realized!"
  fi

  delete_file "/tmp/ggas"
  mkdir -p /tmp/ggas/
  cp -r "$_DEFAULT_PATH/ggas/sql/" /tmp/ggas/
  cd /tmp/ggas

  _IMPROVE_QUERIES="improve_queries.sh"

  wget "$_CENTRAL_URL_TOOLS/scripts/install/ggas/sql/$_IMPROVE_QUERIES"

  chmod +x $_IMPROVE_QUERIES

  ./$_IMPROVE_QUERIES

  rename_versions

  mkdir sql/01 sql/02

  mv sql/GGAS_SCRIPT_INICIAL_ORACLE_0*.sql sql/01/
  mv sql/*.sql sql/02/

  _IMPORT_SCRIPT="import_db.sh"

  wget "$_CENTRAL_URL_TOOLS/scripts/install/ggas/sql/$_IMPORT_SCRIPT"

  chmod +x $_IMPORT_SCRIPT

  mv $_IMPORT_SCRIPT sql/

  print_colorful yellow bold "> You must run the commands in the container Oracle DB. The root password is 'admin'"

  print_colorful yellow bold "> Copy SQL files to container Oracle DB"

  scp -P $_SSH_PORT -r sql root@localhost:/tmp

  print_colorful yellow bold "> Import SQL files to container Oracle DB"

  ssh -p $_SSH_PORT root@localhost "/tmp/sql/import_db.sh"

  delete_file "/tmp/ggas"

  print_colorful yellow bold "> You must run the commands in the container Oracle DB. The root password is 'admin'"

  print_colorful yellow bold "> Copy log file from container Oracle DB"

  LOG_FILE=ggas_import_database.log

  scp -P $_SSH_PORT root@localhost:/tmp/$LOG_FILE $_CURRENT_DIR

  cd "$_CURRENT_DIR"

  [ $? -eq 0 ] && message "Notice" "Import $_APP_NAME database was successful! Log file is in $_CURRENT_DIR/$LOG_FILE"
}

configure_nginx () {
  _PORT=$(grep "jboss.http.port" "/opt/wildfly/standalone/configuration/standalone.xml" | cut -d: -f2 | cut -d'}' -f1)
  _DEFAULT_HOST="localhost:$_PORT"

  if command -v nginx > /dev/null; then
    _DOMAIN=$(input_field "ggas.nginx.domain" "Enter the domain of GGAS" "ggas.company.gov")
    [ $? -eq 1 ] && main
    [ -z "$_DOMAIN" ] && message "Alert" "The domain can not be blank!"

    _HOST=$(input_field "ggas.nginx.host" "Enter the host of GGAS server" "$_DEFAULT_HOST")
    [ $? -eq 1 ] && main
    [ -z "$_HOST" ] && message "Alert" "The host can not be blank!"

    curl -sS "$_CENTRAL_URL_TOOLS/scripts/templates/nginx/redirect.conf" > ggas.conf

    change_file replace ggas.conf APP ggas
    change_file replace ggas.conf DOMAIN "$_DOMAIN"
    change_file replace ggas.conf HOST "$_HOST"

    mv ggas.conf /etc/nginx/conf.d/
    rm ggas.conf*

    admin_service nginx restart

    [ $? -eq 0 ] && message "Notice" "The host is successfully configured in NGINX!"
  else
    message "Alert" "NGINX is not installed! GGAS host not configured!"
  fi
}

main () {
  _TI_FOLDER="/opt/tools-installer"
  _ORACLE_CONFIG="$_TI_FOLDER/oracle.conf"
  _USER_LOGGED=$(run_as_root "echo $SUDO_USER")

  if [ "$(provisioning)" = "manual" ]; then
    tool_check dialog

    _OPTION=$(menu "Select the option" "$_OPTIONS_LIST")

    if [ -z "$_OPTION" ]; then
      clear && exit 0
    else
      $_OPTION
    fi
  else
    [ -n "$(search_app ggas)" ] && install_ggas
    [ "$(search_value ggas.import.database)" = "yes" ] && import_ggas_database
    [ -n "$(search_app ggas.nginx)" ] && configure_nginx
  fi
}

setup
main
