#!/bin/bash

###############################################################################
#                                                                             #
#  This script will delete the domain's directories and data from the system  #
#  files necessary for removing a domain from the system.                     #
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
#  DATE: 07.10.2012                                                           #
#  AUTHOR: Ammon Shepherd                                                     #
#                                                                             #
###############################################################################

# TODO:


set -e

WEBSITES="/websites"
VHOSTFILE="/etc/httpd/conf/virtual_hosts.conf"
HOST="localhost"


# Get the domain name info
echo -n "Enter FQDN of project to remove: "
read fqdn

echo -n "Enter project name: "
read project



# Check if directory exists in /websites and prompt if you're sure you want to delete it
if [ -d "$WEBSITES/$project" ]; then
    echo -n "Are you sure you want to delete the following directory and all its contents: $WEBSITES/$project [y/n]? "
    read reply

    if [[ "$reply" != "y" ]]; then
        echo "Nothing done..."
        exit 1
    fi


    # Remove the user
    echo
    echo "Removing user: $project."
    userdel $project || true
    userdel ${project}_sftp || true
    groupdel $project || true
    groupdel ${project}_sftp || true



    # Remove the info for the vhost from the Apache Vhost file
    echo "Removing record from $VHOSTFILE"
    bork=${fqdn//./\\.}
    sed -i -e"/^# Begin $bork section/,/^# End $bork section/d" $VHOSTFILE


    # Delete the php-fpm conf file
    rm -f /etc/php-fpm.d/${project}.conf





    # Get the MySQL user/pass but don't show it on the CLI
    echo
    echo -n "Enter an existing MySQL user with privileges to create databases and users: "
    read -s DBUSER
    echo
    echo -n "Enter the MySQL pass for that user: "
    read -s DBPASS
    echo

    echo "Making copy of database at $WEBSITES/$project/$project.sql before deleting."
    mysqldump -u$DBUSER -p$DBPASS $project > $WEBSITES/$project/$project.sql || true

    echo "Remove the db user"
    mysql -u$DBUSER -p$DBPASS --execute="DROP USER '$project'@'$HOST';" || true

    mysql -u$DBUSER -p$DBPASS --execute="FLUSH PRIVILEGES;" || true

    echo "Drop the database"
    mysql -u$DBUSER -p$DBPASS --execute="DROP DATABASE $project;" || true

    echo "Making backup of project directory at $WEBSITES/$project.tar.bz2 before deleting."
    tar -cjf $WEBSITES/$project.tar.bz2 $WEBSITES/$project/ || true
    rm -rf $WEBSITES/$project || true



else 
    echo "Nothing to do, $WEBSITES/$project does not exist"
    exit 1
fi
echo

exit
