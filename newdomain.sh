#!/bin/bash

###############################################################################
#                                                                             #
#  This script will create the proper directories and add data to the system  #
#  files necessary for adding a new domain to the system.                     #
#                                                                             #
#  This script assumes Apache, PHP-FPM, and MySQL are being used.             #
#                                                                             #
#  All that remains, is for the user to test the Apache config with           #
#                                                                             #
#    service httpd configtest                                                 #
#                                                                             #
#  If everything is kosher, restart apache like so:                           #
#                                                                             #
#    service httpd graceful                                                   #
#                                                                             #
#                                                                             #
#  DATE: 02.18.2014                                                           #
#  AUTHOR: Ammon Shepherd                                                     #
#                                                                             #
###############################################################################

# TODO:
#   - Add the info into virtual_hosts.conf alphabetically


set -e

WEBSITES="/websites"
VHOSTFILE="/etc/httpd/conf/virtual_hosts.conf"
PHP_FPM_PATH="/etc/php-fpm.d"
UHOST="localhost"
HOST="localhost"



# Get the domain name info

read -e -p "Enter FQDN for project (ex. 'somedomain.com' or 'newsite.org'): " fqdn


# Test the project input for proper length and characters. MySQL requires less
# than 16 characters for a user name. Many command line tools (top, mytop, etc)
# only show user names <= 8 chars. 
while [ "$projpass" != "pass" ]; do
    projpass='pass'

    read -e  -p "Enter project name (ex. 'somedomain' or 'newsite') this becomes the user/group: " project

    # Check project is only alphanumeric
    if [[ $project =~ [^0-9a-z]+ ]]; then
        echo "Project name must be numbers and letters only, and less than 11 characters."
        projpass='fail'
        continue
    fi

    # Check user name for size
    lngth=${#project}
    if [ "$lngth" -gt "11" -o "$lngth" -lt "1" ]; then
        echo "Project name must be less than 11 and more than 0 characters."
        echo
        projpass='fail'
    fi

    echo 
done


# Create the domain folders
if [ ! -d "$WEBSITES/$project" ]; then
    mkdir -p $WEBSITES/$project/{home,www,var}
    mkdir -p $WEBSITES/$project/var/{tmp,phpsessions}
fi


PROJROOT="$WEBSITES/$project"
PROJHOME="$WEBSITES/$project/home"
PROJWWW="$WEBSITES/$project/www"
PROJVAR="$WEBSITES/$project/var"
NEW_USER=$project
NEW_PASS=`cat /dev/urandom | tr -cd "[:alnum:]!@#$%^*()" | head -c 20`

# Create the user, change root'ed to /websites/$project by the "projects" group
echo
echo "Creating user: $project."
# options: -M don't create home directory, -c comment, -G group, -d home directory, -s shell
useradd -M -c "$fqdn" -G projects -d $PROJROOT -s /bin/false $project || true

# Create sftp user for project. Change root'ed to /websites/$project by the
# "sftponly" group, and allowed to edit the web files by group "$project"
echo
echo "Creating sftp user."
useradd -M -c "SFTP user for $fqdn" -G sftponly,${project} -d ${PROJROOT} -s /bin/false "${project}_sftp" || true
echo $NEW_PASS | passwd "${project}_sftp" --stdin || true


# Put the account info in a file 
echo
echo "Putting account info in $PROJHOME/account.info"
echo -e "# An SFTP account has been created. This account info can be used to access the server.\nuser:${project}_sftp password:$NEW_PASS host:$fqdn" > $PROJHOME/account.info

# Fix permissions on the project folders
chown root:root $PROJROOT
chmod 755 $PROJROOT

chown -R ${project}:${project} $PROJVAR
chmod -R 755 $PROJVAR

chown -R ${project}_sftp:${project}_sftp $PROJHOME
chmod -R 750 $PROJHOME
chmod 440 $PROJHOME/account.info

chown -R $project:$project $PROJWWW
chmod -R g+w+s $PROJWWW



# replace . with \. in the FQDN
bork=${fqdn//./\\.}

# The info for the new vhost
VHOSTINFO='

# Begin '$fqdn' section
<VirtualHost *:80>
    DocumentRoot '$PROJWWW'/
    ServerName '$fqdn'
    ServerAlias www.'$fqdn'

    RewriteEngine On
    RewriteCond %{HTTP_HOST}    !^'$bork'$ [NC]
    RewriteRule ^/(.*)  http://'$fqdn'/$1 [R=301]

    ErrorLog /logs/apache/current/'$fqdn'-error_log
    CustomLog /logs/apache/current/'$fqdn'-access_log combined

    <IfModule mod_fastcgi.c>
        SuexecUserGroup '$project' '$project'
        <FilesMatch \.php$>
            SetHandler php-fastcgi
        </FilesMatch>
        Action php-fastcgi /php-fpm
        Alias   /php-fpm   '$PROJVAR'/php.fpm
        FastCGIExternalServer '$PROJVAR'/php.fpm -socket '$PROJVAR'/php-fpm.sock -user '$project' -group '$project'
        AddType application/x-httpd-fastphp5 .php
        <Directory "'$PROJVAR'">
            Order deny,allow
            Deny from all
            <Files "php.fpm">
                Order allow,deny
                Allow from all
            </Files>
        </Directory>
    </IfModule>
</VirtualHost>
# End '$fqdn' section'

# Append to the virtual_host.conf
# ToDo: Add the entry in alphabetically!
echo "Adding VHOST entry to $VHOSTFILE ..."
echo "$VHOSTINFO" >> $VHOSTFILE




# Create the php-fpm conf file
echo "Creating php-fpm conf file"
cp $PHP_FPM_PATH/www.conf $PHP_FPM_PATH/${project}.conf
php_fpm_conf="${PHP_FPM_PATH}/${project}.conf"
# escape the forward slashes in the PROJROOT variable so the sed search/replace
# below works. 
proj_var=${PROJVAR//\//\\/}
proj_root=${PROJROOT//\//\\/}
sed -i -e"s/\[www\]/[${project}]/" $php_fpm_conf
sed -i -e"s/listen = 127.0.0.1:9000/listen = ${proj_var}\/php-fpm.sock/" $php_fpm_conf
sed -i -e"s/user = apache/user = ${project}/" $php_fpm_conf
sed -i -e"s/group = apache/group = ${project}/" $php_fpm_conf
sed -i -e"s/slowlog = \/var\/log\/php-fpm\/www-slow.log/slowlog = ${proj_var}\/php-fpm-slow.log/" $php_fpm_conf
#sed -i -e"s/;chroot =/chroot = $proj_root/" $php_fpm_conf
# delete some lines from the conf file
sed -i -e"/php_value\[session.save_path\]/d" $php_fpm_conf
sed -i -e"/php_admin_value\[error_log\]/d" $php_fpm_conf
sed -i -e"/php_admin_value\[memory_limit\]/d" $php_fpm_conf
# add some lines from the conf file
echo "php_admin_value[auto_prepend_file] = ${PROJVAR}/phpfix" >> $php_fpm_conf
echo "php_admin_value[upload_tmp_dir]    = ${PROJVAR}/tmp" >> $php_fpm_conf
echo "php_value[session.save_path]       = ${PROJVAR}/phpsessions" >> $php_fpm_conf
echo "php_admin_value[error_log]         = ${PROJVAR}/php-error.log" >> $php_fpm_conf
echo "php_admin_value[doc_root]          = ${PROJWWW}" >> $php_fpm_conf
echo "" >> $php_fpm_conf
echo "php_admin_value[upload_max_filesize] = 16M" >> $php_fpm_conf
echo "php_admin_value[cgi.fix_pathinfo]    = 0" >> $php_fpm_conf
echo "php_admin_value[post_max_size]       = 16M" >> $php_fpm_conf
echo "php_admin_value[date.timezone]       = America/New_York" >> $php_fpm_conf


echo "Creating phpfix file"
# Create the phpfix file
phpfix='<?php
$_SERVER["DOCUMENT_ROOT"] = ini_get("doc_root");
$_SERVER["PATH_TRANSLATED"] = str_replace($_SERVER["HOME"], "", $_SERVER["PATH_TRANSLATED"]);
$_SERVER["SCRIPT_NAME"] = str_replace($_SERVER["SCRIPT_NAME"], $_SERVER["PHP_SELF"], $_SERVER["SCRIPT_NAME"]);
$_SERVER["SCRIPT_FILENAME"] = str_replace($_SERVER["SCRIPT_FILENAME"], $_SERVER["DOCUMENT_ROOT"].$_SERVER["SCRIPT_NAME"], $_SERVER["SCRIPT_FILENAME"]);
?>'
echo "$phpfix" > $PROJVAR/phpfix


# Get the MySQL user/pass but don't show them on the CLI
echo
read -e -s -p "Enter an existing MySQL user with privileges to create databases and users: " DBUSER
echo
read -e -s  -p "Enter the MySQL pass for that user: " DBPASS
echo

echo "Creating the database and user account..."
mysql -u$DBUSER -p$DBPASS --execute="CREATE DATABASE IF NOT EXISTS $project;"

mysql -u$DBUSER -p$DBPASS --execute="GRANT ALL PRIVILEGES ON $project . * TO '$NEW_USER'@'$UHOST' IDENTIFIED BY '$NEW_PASS';"
# FOR MONTI/CELLO: comment the line above, and uncomment the line below.
#mysql -u$DBUSER -p$DBPASS --execute="GRANT ALL PRIVILEGES ON $project . * TO '$NEW_USER'@'%.localdomain' IDENTIFIED BY '$NEW_PASS';"
mysql -u$DBUSER -p$DBPASS --execute="FLUSH PRIVILEGES;"


# Put MySQL account info in a file
echo "Putting MySQL account info in $PROJHOME/mysql.info"
echo "user:$NEW_USER password:$NEW_PASS database:$project host:$HOST" > $PROJHOME/mysql.info
chown ${project}_sftp:${project}_sftp $PROJHOME/mysql.info
chmod 440 $PROJHOME/mysql.info

echo
echo
echo "Test Apache configuration with: service httpd configtest"
echo "If everything looks kosher, then restart Apache with: service httpd graceful"
echo
echo "Next, on CHNMDEV, create the appropriate entry in /stats/awstats/configs/HOST/config.inc"
echo "Then, run the /stats/awstats/configs/HOST/generate_awstats_configs script"
echo

exit
