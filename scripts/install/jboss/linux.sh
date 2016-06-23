#!/bin/bash

# https://www.jboss.org/
# http://wildfly.org/
# http://unix.stackexchange.com/questions/32908/how-to-insert-the-content-of-a-file-into-another-file-before-a-pattern-marker

_APP_NAME="JBoss"
_OPT_FOLDER="/opt"
_JBOSS_FOLDER="$_OPT_FOLDER/jboss"
_JBOSS4_DESCRIPTION="JBoss 4.0.1SP1"
_WILDFLY_DESCRIPTION="8.2.1.Final"
_PORT_DEFAULT="1099"
_RMI_PORT_DEFAULT="1098"
_OPTIONS_LIST="install_jboss4 'Install $_JBOSS4_DESCRIPTION' \
               configure_jboss4 'Configure $_JBOSS4_DESCRIPTION' \
               install_wildfly8 'Install WildFly $_WILDFLY_DESCRIPTION'"

setup () {
  [ -z "$_CENTRAL_URL_TOOLS" ] && _CENTRAL_URL_TOOLS="http://prodigasistemas.github.io"

  ping -c 1 $(echo $_CENTRAL_URL_TOOLS | sed 's|http.*://||g' | cut -d: -f1) > /dev/null
  [ $? -ne 0 ] && echo "$_CENTRAL_URL_TOOLS connection was not successful!" && exit 1

  _FUNCTIONS_FILE="/tmp/.tools.installer.functions.linux.sh"

  curl -sS $_CENTRAL_URL_TOOLS/scripts/functions/linux.sh > $_FUNCTIONS_FILE 2> /dev/null
  [ $? -ne 0 ] && echo "Functions were not loaded!" && exit 1

  [ -e "$_FUNCTIONS_FILE" ] && source $_FUNCTIONS_FILE && rm $_FUNCTIONS_FILE

  os_check
}

install_jboss4 () {
  _CURRENT_DIR=$(pwd)

  java_check 6

  confirm "Do you confirm the installation of $_JBOSS4_DESCRIPTION?"
  [ $? = 1 ] && main

  _JBOSS_FILE="jboss-4.0.1sp1"

  backup_folder "$_OPT_FOLDER/$_JBOSS_FILE"

  cd $_OPT_FOLDER

  wget http://downloads.sourceforge.net/project/jboss/JBoss/JBoss-4.0.1SP1/$_JBOSS_FILE.zip

  unzip -o $_JBOSS_FILE.zip

  rm $_JBOSS_FILE.zip

  ln -sf $_JBOSS_FILE jboss

  cd $_CURRENT_DIR

  [ $? -eq 0 ] && message "Notice" "$_JBOSS4_DESCRIPTION successfully installed!"
}

configure_jboss4 () {
  _CURRENT_DIR=$(pwd)
  _USER_LOGGED=$(run_as_root "echo $SUDO_USER")

  [ ! -e "$_JBOSS_FOLDER" ] && message "Alert" "Folder $_JBOSS_FOLDER not exists!"

  jboss_check 4

  _OWNER=$(input_field "jboss.config.owner" "Enter the JBoss owner name" "$_USER_LOGGED")
  [ $? -eq 1 ] && main
  [ -z "$_OWNER" ] && message "Alert" "The JBoss owner name can not be blank!"

  _JAVA_OPTS_XMS=$(input_field "jboss.config.java.opts.xms" "Enter the Java Opts XMS" "512m")
  [ $? -eq 1 ] && main
  [ -z "$_JAVA_OPTS_XMS" ] && message "Alert" "The Java Opts XMS can not be blank!"

  _JAVA_OPTS_XMX=$(input_field "jboss.config.java.opts.xmx" "Enter the Java Opts XMX" "1024m")
  [ $? -eq 1 ] && main
  [ -z "$_JAVA_OPTS_XMX" ] && message "Alert" "The Java Opts XMX can not be blank!"

  _JAVA_OPTS_MAX_PERM_SIZE=$(input_field "jboss.config.java.opts.max.perm.size" "Enter the Java Opts Max Perm Size" "512m")
  [ $? -eq 1 ] && main
  [ -z "$_JAVA_OPTS_MAX_PERM_SIZE" ] && message "Alert" "The Java Opts Max Perm Size can not be blank!"

  _PORT=$(input_field "jboss.config.port" "Enter the port (default: $_PORT_DEFAULT)" "8098")
  [ $? -eq 1 ] && main
  [ -z "$_PORT" ] && message "Alert" "The port can not be blank!"

  _RMI_PORT=$(input_field "jboss.config.rmi.port" "Enter the rmi port (default: $_RMI_PORT_DEFAULT)" "8099")
  [ $? -eq 1 ] && main
  [ -z "$_RMI_PORT" ] && message "Alert" "The rmi port can not be blank!"

  confirm "Do you confirm the configuration of $_JBOSS4_DESCRIPTION?"
  [ $? = 1 ] && main

  # Insert standardjboss.xml
  _ORIGIN_FILE="$_JBOSS_FOLDER/server/default/conf/standardjboss.xml"
  _INSERT_FILE="insert-standardjboss.xml"
  _SEARCH="Uncomment to use JMS message inflow from jmsra.rar"

  curl -sS "$_CENTRAL_URL_TOOLS/scripts/templates/jboss/standardjboss.xml" > $_INSERT_FILE

  [ ! -e "$_ORIGIN_FILE" ] && message "Alert" "$_ORIGIN_FILE not found!"
  [ ! -e "$_INSERT_FILE" ] && message "Alert" "$_INSERT_FILE not found!"

  cp $_ORIGIN_FILE "$_ORIGIN_FILE.backup"

  _LINE=$(cat $_ORIGIN_FILE | grep -n "$_SEARCH" | cut -d: -f1)

  { head -n $(($_LINE-1)) $_ORIGIN_FILE; cat $_INSERT_FILE; tail -n +$_LINE $_ORIGIN_FILE; } > .tempfile

  mv .tempfile $_ORIGIN_FILE

  rm $_INSERT_FILE

  # Change config params
  _RUN_FILE="$_JBOSS_FOLDER/bin/run.conf"
  _ORIGIN_CONFIG=$(cat $_RUN_FILE | sed '/^ *#/d' | egrep "JAVA_OPTS=")
  change_file "replace" "$_RUN_FILE" "$_ORIGIN_CONFIG" "   JAVA_OPTS=\"-server -Xms${_JAVA_OPTS_XMS} -Xmx${_JAVA_OPTS_XMX} -XX:MaxPermSize=${_JAVA_OPTS_MAX_PERM_SIZE}\""

  _SERVICE_FILE="$_JBOSS_FOLDER/server/default/conf/jboss-service.xml"
  change_file "replace" "$_SERVICE_FILE" "<attribute name=\"Port\">$_PORT_DEFAULT</attribute>" "<attribute name=\"Port\">$_PORT</attribute>"
  change_file "replace" "$_SERVICE_FILE" "<attribute name=\"RmiPort\">$_RMI_PORT_DEFAULT</attribute>" "<attribute name=\"RmiPort\">$_RMI_PORT</attribute>"

  # Copy files from jboss-libs
  cd /tmp && wget https://github.com/prodigasistemas/jboss-libs/archive/master.zip

  unzip master.zip && rm master.zip

  export JBOSS_HOME=$_JBOSS_FOLDER

  _FIND_JBOSS_HOME=$(cat /etc/rc.local | grep JBOSS_HOME)
  if [ -z "$_FIND_JBOSS_HOME" ]; then
    if [ "$_OS_TYPE" = "deb" ]; then
      change_file "append" "/etc/rc.local" "# By default this script does nothing." "export JBOSS_HOME=$_JBOSS_FOLDER"
    elif [ "$_OS_TYPE" = "rpm" ]; then
      run_as_root "echo \"export JBOSS_HOME=$_JBOSS_FOLDER\" >> /etc/rc.local"
    fi
  fi

  cd jboss-libs-master/ && bash copiar-libs-para-jboss.sh

  rm -rf /tmp/jboss-libs-master/

  # Configure jboss user
  _FIND_JBOSS_USER=$(cat /etc/passwd | grep ^jboss)
  [ -z "$_FIND_JBOSS_USER" ] && adduser jboss

  # Configure owner user
  _FIND_USER=$(cat /etc/passwd | grep ^$_OWNER)

  [ -z "$_FIND_USER" ] && adduser $_OWNER

  # Configure initializer script
  chmod +x $_JBOSS_FOLDER/bin/*.sh

  if [ "$_OS_TYPE" = "deb" ]; then
    _SCRIPT_NAME="jboss_init_debian.sh"

    if [ "$_OWNER" != "jenkins" ]; then
      change_file "replace" "$_JBOSS_FOLDER/bin/$_SCRIPT_NAME" "jenkins" "$_OWNER"
    fi
  fi

  [ "$_OS_TYPE" = "rpm" ] && _SCRIPT_NAME="jboss_init_redhat.sh"

  ln -sf $_JBOSS_FOLDER/bin/$_SCRIPT_NAME /etc/init.d/jboss

  _REAL_JBOSS_FOLDER=$(echo $(ls -l /opt/jboss | cut -d'>' -f2))

  chown $_OWNER:$_OWNER -R "$_OPT_FOLDER/$_REAL_JBOSS_FOLDER"

  register_service jboss

  run_as_user $_OWNER "JBOSS_HOME=$_JBOSS_FOLDER /etc/init.d/jboss start"

  cd $_CURRENT_DIR

  [ $? -eq 0 ] && message "Notice" "$_JBOSS4_DESCRIPTION successfully configured!"
}

install_wildfly8 () {
  _CURRENT_DIR=$(pwd)

  java_check 7

  confirm "Do you confirm the installation of WildFly 8?"
  [ $? = 1 ] && main

  _WILDFLY_FILE=$_WILDFLY_DESCRIPTION

  backup_folder "$_OPT_FOLDER/wildfly-$_WILDFLY_FILE"

  cd $_OPT_FOLDER

  wget http://download.jboss.org/wildfly/$_WILDFLY_FILE/wildfly-$_WILDFLY_FILE.tar.gz

  tar -xvzf "wildfly-$_WILDFLY_FILE.tar.gz"

  rm "wildfly-$_WILDFLY_FILE.tar.gz"

  ln -sf "wildfly-$_WILDFLY_FILE" wildfly

  cd $_CURRENT_DIR

  [ $? -eq 0 ] && message "Notice" "WildFly 8 successfully installed!"
}

main () {
  tool_check wget
  tool_check unzip
  tool_check dialog

  if [ "$(provisioning)" = "manual" ]; then
    _OPTION=$(menu "Select the option" "$_OPTIONS_LIST")

    if [ -z "$_OPTION" ]; then
      clear && exit 0
    else
      $_OPTION
    fi
  else
    if [ "$(search_value jboss.version)" = "4" ]; then
      install_jboss4
      [ ! -z "$(search_app jboss.config)" ] && configure_jboss4
    fi
    [ "$(search_value jboss.version)" = "8" ] && install_wildfly8
  fi
}

setup
main
