#!/bin/bash

#Script para automatizar a criação da aplicação utilizando a AZ CLI

echo "[+] Iniciando deployment das aplicações:
	- WEBAPPS
	- REACTJS IN STOTAGE ACCOUNT"

#Coleta lista de usuarios logados na Azure via CLI
USERS=`az account list| jq .[].user.name| wc -l`

#Caso não haja usuario logado, solicita login
if [ "$USERS" -eq 0 ] ; then
	echo "[-] Necessario configurar usuarios para uso do AZ CLI!"
	bash login_az.sh
fi

#Mostra usuario autenticado
USER=`az account list| jq -r '.[] | [.isDefault, .user.name]'| grep -A1 true| tail -1| tr -d '\n,\r" '`
echo "[+] Usuario default autenticado: $USER"

#Verifica se ha recursos criados
RES=`cat infrastructure/terraform.tfstate | jq 'select(.resources != [] )  .resources' | wc -l`

if [ $RES -eq 0 ] ; then
	echo "[!!] Não há recursos criados, execute o terraform plan/apply"
	echo "	[1] - Ajuste as variaveis do arquivo infrastructure/variables.auto.tfvars"
	echo "	[2] - entre no diretorio infrastructure/"
	echo "	[3] - Execute terraform plan"
	echo "	[4] - Execute terraform apply"
	echo "	[5] - execute o script novamente: $0"
        exit 1
fi	

#Coletando variaveis para criação dos recursos (Melhorar posteriormente com "jq")
WEB_APP=`grep primary_web_endpoint infrastructure/terraform.tfstate |  cut -d ":" -f2,3| tr -d ',"\n\r'`
RG=`grep rg_name infrastructure/variables.auto.tfvars | cut -d "=" -f2| tr -d ' "\n\r'`
APP_NAME=`grep default_hostname infrastructure/terraform.tfstate | cut -d ":" -f2,3| tr -d ',"\r\n'| cut -d "." -f1| tr -d '\n\r'`
DB_HOST=$(host `grep database.azure.com infrastructure/terraform.tfstate | cut -d ":" -f2| tr -d ' ",'`| cut -d " " -f4| head -1)
DB_USER=`grep db_username infrastructure/variables.auto.tfvars | cut -d "=" -f2| tr -d '" \n\r'`
DB_PASS=`grep db_password infrastructure/variables.auto.tfvars | cut -d "=" -f2| tr -d '" \n\r'`
DB_NAME=`grep fqdn infrastructure/terraform.tfstate| cut -d ":" -f2| tr -d '\n\r" '| cut -d "." -f1`
#Monta string da API
echo 'DATABASE_URI="postgresql://'$DB_USER':'$DB_PASS'@'$DB_HOST'/postgres?sslmode=require"' > back-end/web-api/.env
APP_STRING=`cat back-end/web-api/.env | cut -d "=" -f2` 
ST_NAME=`cat infrastructure/terraform.tfstate | grep primary_web_endpoint| cut -d ":" -f2,3| tr -d ',"'| cut -d "." -f1| cut -d "/" -f3`
echo "[!!] Verifique os valores do deployment: "

echo "WEB URL: $WEB_APP
      RESOURCE GROUP: $RG
      APP NAME: $APP_NAME
      STORAGE ACCOUNT: $ST_NAME
      STRING DE CONEXÂO: $APP_STRING
      "

#Confirma a criação da app
read -p "[!!] Os dados acima estão corretos? Deseja continuar o deploy? [s/n]: " resp
resp=`echo $resp | tr [A-Z] [a-z]`
if [ "$resp" == "s" ] ; then
	echo "[+] Voce respondeu $resp, iniciando o deploy."
else
	echo "[-] Ok, saindo..."
	exit 1
fi

#Inicia criação da webapp
cd back-end/web-api/
rm -rf .azure
az webapp config appsettings set --resource-group "$RG" --name $APP_NAME --settings SCM_DO_BUILD_DURING_DEPLOYMENT=true
#cat .env
#Criando variavel de strinf de conexão
az webapp config appsettings set  --name $APP_NAME --settings DATABASE_URI=$APP_STRING --resource-group $RG
az webapp config set --name $APP_NAME --resource-group $RG --startup-file startup.sh
#Publicando a aplicação
echo "Subindo aplicação em WEBAPPS"
az webapp up --resource-group $RG --name $APP_NAME

#Libera regra para serviços do Azure
az postgres flexible-server firewall-rule create --resource-group $RG \
                                        --server-name $DB_NAME \
                                        --name AllowAllWindowsAzureIps \
                                        --start-ip-address 0.0.0.0 \
                                        --end-ip-address 0.0.0.0

#Cria aplicação estatica e adiciona em storage account
cd ../../front-end/customer-app
echo "REACT_APP_API_URI=\"$WEB_APP" > .env
#Build da aplicação
npm run build
cd public
#Adiciona o index.html no storage account
az storage blob service-properties update --account-name $ST_NAME --static-website  --index-document index.html
cd ..
#Movendo arquivos do build para o storage account
az storage blob upload-batch --account-name $ST_NAME -s ./build -d '$web' --overwrite

echo "[+] FRONTEND: $WEB_APP

