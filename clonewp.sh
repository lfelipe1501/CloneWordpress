#!/bin/bash

#
# Script to clone a wordpress site
#
# @author   Luis Felipe <lfelipe1501@gmail.com>
# @website  https://www.lfsystems.com.co
# @version  1.0

#Color variables
W="\033[0m"
B='\033[0;34m'
R="\033[01;31m"
G="\033[01;32m"
OB="\033[44m"
OG='\033[42m'
UY='\033[4;33m'
UG='\033[4;32m'

#Check if you are in the directory where wordpress was installed
FILE='wp-config.php'
if [ -f "$FILE" ]; then

#get files and folders owner and group for actual wordpress installation
file_meta=($(ls -l $FILE)) 
file_owner="${file_meta[2]}" # get User
file_group="${file_meta[3]}" # get Group

#Get DB_NAME, DB_USER and DB_PASS inside the wp-config file.
db_name=$(sed -n "s/define( *'DB_NAME', *'\([^']*\)'.*/\1/p" $FILE)
db_user=$(sed -n "s/define( *'DB_USER', *'\([^']*\)'.*/\1/p" $FILE)
db_pass=$(sed -n "s/define( *'DB_PASSWORD', *'\([^']*\)'.*/\1/p" $FILE)

echo -e "==================================\n$OB Wordpress Clone$W \n=================================="
echo ""

##Checking if it is on a cpanel or a normal linux

if ! command -v uapi &> /dev/null
then
    echo -e "You are on a $R Linux without cPanel$W \n$UY>> in order to use this script it must be executed on a linux with cpanel$W\n"
    exit 1
else

    ##Copy files to new location
    new_location_prompt() {
        apwd=$(pwd)
        echo "Please indicate the new Directory..."
        read -p "$(echo -e "Complete Target Directory (e.g. without the last slash $OB"$apwd"/newSite2$W): \n> ")" target_directory
        NewLocation=${target_directory}
        
        prompt_confirm
    }
    
    prompt_confirm() {
        read -p "is this new location correct? [y/n] " response
        case "$response" in
            [yY])
                echo -e "==================================\n$OB Duplicating the directory...$W \n=================================="
                echo -e "$G>> Copying...$W please wait.....\n"
                
                # check script is being run by root or normal user
                if [[ $EUID -ne 0 ]]; then
                    cp -r . $NewLocation && chown -R $file_owner:$file_group $NewLocation;
                else
                    rsync --include='.*' --stats -a * $NewLocation/ && chown -R $file_owner:$file_group $NewLocation;
                fi
                
                find $NewLocation -type d -exec chmod 755 {} \;
                find $NewLocation -type f -exec chmod 644 {} \;
                echo ""
                echo "All ready!, the new location is: $NewLocation"
                echo ""
                ;;
            [nN])
                echo ""
                new_location_prompt
                ;;
            *)
                echo ""
                echo "please select Yes[y] or Not[n]?"
                prompt_confirm
                ;;
        esac
    }
    
    new_location_prompt

    ## Generate new URL and New Database

    new_url_prompt() {
        echo "Please indicate the new URL of WebSite..."
        read -p "$(echo -e "Complete Site URL (e.g. without the last slash$R https://newsite.com$W or$R https://site.com/wp2$W): \n> ")" target_directory
        new_URL="$target_directory"
        
        prompt_confirm_url
    }
    
    prompt_confirm_url() {
        read -p "is this new URL correct? [y/n] " response
        case "$response" in
            [yY]) 
                ##Generate db and user with random numbers
                rnumber=$((RANDOM%995+1))
                nwdt="$file_owner"_wps"$rnumber"
                
                echo -e "==================================\n$OB Duplicating the database...$W \n=================================="
                echo -e "$G>> Duplicating...$W please wait.....\n"
                
                ##Create database and user with privileges
                
                # check script is being run by root or normal user
                if [[ $EUID -ne 0 ]]; then
                    uapi Mysql create_database name="$nwdt" &> /dev/null
                    uapi Mysql create_user name="$nwdt" password="$db_pass" &> /dev/null
                    uapi Mysql set_privileges_on_database user="$nwdt" database="$nwdt" privileges=ALL &> /dev/null
                else
                    uapi --user="$file_owner" Mysql create_database name="$nwdt" &> /dev/null
                    uapi --user="$file_owner" Mysql create_user name="$nwdt" password="$db_pass" &> /dev/null
                    uapi --user="$file_owner" Mysql set_privileges_on_database user="$nwdt" database="$nwdt" privileges=ALL &> /dev/null
                fi
                
                ##Dump original database to the new database
                mysqldump $db_name -u $db_user -p$db_pass > "$db_name"_orig.sql
                mysql $nwdt -u $nwdt -p$db_pass < "$db_name"_orig.sql
                
                #Delete generated database dump file
                rm -rf "$db_name"_orig.sql
                
                echo -e "==================================\n$OB Creating new URL...$W \n=================================="
                
                ## Set new URL to DB:
                db_prefix=$(grep table_prefix $FILE |awk -F"'|'" '{print$2}')
                old_URL=$(mysql $db_name -u $db_user -p$db_pass -se "SELECT option_value FROM "$db_prefix"options WHERE option_name LIKE '%siteurl%'")
                
                SQLUpdate1="UPDATE "$db_prefix"options SET option_value = replace(option_value, '$old_URL', '$new_URL') WHERE option_name = 'home' OR option_name = 'siteurl';"
                SQLUpdate2="UPDATE "$db_prefix"posts SET guid = replace(guid, '$old_URL', '$new_URL');"
                SQLUpdate3="UPDATE "$db_prefix"posts SET post_content = replace(post_content, '$old_URL', '$new_URL');"
                SQLUpdate4="UPDATE "$db_prefix"postmeta SET meta_value = replace(meta_value,'$old_URL', '$new_URL');"
                
                ##Excute SQL Update query
                mysql $nwdt -u $nwdt -p$db_pass -se "${SQLUpdate1}${SQLUpdate2}${SQLUpdate3}${SQLUpdate4}"
                
                ##Set the new User and DB in wp-config file
                sed -i -e "s/$db_name/$nwdt/g" $NewLocation/$FILE
                sed -i -e "s/$db_user/$nwdt/g" $NewLocation/$FILE
                
                echo ""
                echo "All ready!, the new URL is: $new_URL"
                echo "You can also enter the administrator: ${new_URL}/wp-admin"
                echo ""
                ;;
            [nN])
                echo ""
                new_url_prompt
                ;;
            *)
                echo ""
                echo "please select Yes[y] or Not[n]?"
                prompt_confirm_url
                ;;
        esac
    }
    new_url_prompt
fi
rm -rf clonewp.sh
echo -e "\nCleaning and deleting files and folders created by this script\n$UG>> everything is ready!....$W\n"

else 
    echo -e "\n$FILE does not exist."
    echo -e "REMEMBER: in order to use this script, you must place it inside the folder where the WordPress was installed\nFor example:$B /var/www/html/wordp$W or$B /home/user/public_html$W"
    exit 1
fi
