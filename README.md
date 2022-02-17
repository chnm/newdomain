# Archived
RRCHNM archived this repository in February 2022. Last actual code activity was February 2014. If you need more information or to unarchive this repository, please contact us at webmaster at chnm.gmu.edu

# Create a New Domain on the server

This script will create a new Apache, PHP-FPM, MySQL environment on the server for a new domain. It does the following things:

* Create a directory structure like the following [permissions owner group]:

````
/websites/ [drwxr-xr-x root root] 
 └── testsite [drwxr-xr-x root root] 
├── home [drwxr-x--- testsite_sftp testsite_sftp]
│   ├── account.info [-r--r----- testsite_sftp testsite_sftp]
│   └── mysql.info [-r--r----- testsite_sftp testsite_sftp]
├── var [drwxr-xr-x testsite testsite]
│   ├── phpfix [-rw-r--r-- root root]
│   ├── phpsessions [drwxr-xr-x testsite testsite]
│   └── tmp [drwxr-xr-x testsite testsite]
└── www [drwxrwsr-x testsite testsite]
````

* Create a user and sftp user for the domain: projectname and projectname_sftp
* Add a new entry in virtual_hosts.conf

````
# Begin testsite.local section
<VirtualHost *:80>
    DocumentRoot /websites/testsite/www/
    ServerName testsite.local
    ServerAlias www.testsite.local

    RewriteEngine On
    RewriteCond %{HTTP_HOST}    !^testsite\.local$ [NC]
    RewriteRule ^/(.*)  http://testsite.local/$1 [R=301]

    ErrorLog /logs/apache/current/testsite.local-error_log
    CustomLog /logs/apache/current/testsite.local-access_log combined

    <IfModule mod_fastcgi.c>
        SuexecUserGroup testsite testsite
        <FilesMatch \.php$>
            SetHandler php-fastcgi
        </FilesMatch>
        Action php-fastcgi /php-fpm
        Alias   /php-fpm   /websites/testsite/var/php.fpm
        FastCGIExternalServer /websites/testsite/var/php.fpm -socket /websites/testsite/var/php-fpm.sock -user testsite -group testsite
        AddType application/x-httpd-fastphp5 .php
        <Directory "/websites/testsite/var">
            Order deny,allow
            Deny from all
            <Files "php.fpm">
                Order allow,deny
                Allow from all
            </Files>
        </Directory>
    </IfModule>
</VirtualHost>
# End testsite.local section
````

* Copy and edit a new php-fpm pool configuration file

*Lines to change*

````
[www] => [testsite]
listen = 127.0.0.1:9000 => listen = /websites/testsite/var/php-fpm.sock/
user = apache => user = testsite
group = apache => group = testsite
slowlog = /var/log/php-fpm/www-slow.log => slowlog = /websites/testsite/var/php-fpm-slow.log
````

*Add the following new lines*

````
php_admin_value[auto_prepend_file] = /websites/testsite/var/phpfix
php_admin_value[upload_tmp_dir]    = /websites/testsite/var/tmp
php_value[session.save_path] = /websites/testsite/var/phpsessions
php_admin_value[error_log]= /websites/testsite/var/php-error.log
php_admin_value[doc_root] = /websites/testsite/www/
php_admin_value[upload_max_filesize] = 16M
php_admin_value[cgi.fix_pathinfo] = 0
php_admin_value[post_max_size] = 16M
php_admin_value[date.timezone] = America/New_York
````

* Create a phpfix file in the /websites/testsite/var/ directory
* Set up the MySQL user and database
