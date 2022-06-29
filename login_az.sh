read -sp "Azure password: " AZ_PASS && echo && az login -u $AZ_LOGIN -p $AZ_PASS
