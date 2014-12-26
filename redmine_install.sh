#! /bin/bash

function install_dependances
{
  # Installation des dépendances sous Debian Wheezy

  packages='build-essential bison openssl curl git-core zlib1g '
  packages+='zlib1g-dev screen libruby libcurl4-openssl-dev libssl-dev '
  packages+='libmysqlclient-dev libxml2-dev libmagickwand-dev libpq5 libpq-dev'
  packages+=' rbenv ruby-build ruby-dev'
  # On effectue une simulation '-s' avant installation des dépendances
  apt-get update && apt-get upgrade -y &&
  apt-get install -ys $packages && apt-get install -y $packages &&
  return 0
  return 1
}

function install_postgresql-client
{
  # Installation du client de postgresql sous Debian Wheezy

  # on vérifie préalablement sa présence
  dpkg --list postresql-client > /dev/null 2>&1 
  [ $? = 1 ] && apt-get install -y postgresql-client
  [ $? = 0 ] && return 0 || return 1
}

function manage_database
{
  # Lance le script de gestion des comptes et bases de données
  # Dépendance :
  #   - Script : ./pgmanage.sh

  # Crée le compte utilisateur et la base de données
  ./pgmanage.sh -h ${db_host} -p 5432 -U postgres -W ${db_postgres_password} \
  -d ${db_name} -u ${db_user} -w ${db_user_password} \
  create_user create_db
}

function config_proxy
{
  # Configure le proxy

  if [ $proxy_url ] ; then
    export http_proxy=$proxy_url
    export https_proxy=$proxy_url
  fi
}

function reset_proxy
{
  # Réinitialise le proxy

  export http_proxy=''
  export https_proxy=''
}

function wget_redmine
{
  # Récupère, décompresse et renomme l'archive de l'application

  cd /$HOME
  wget -O redmine.tgz http://www.redmine.org/releases/redmine-2.5.1.tar.gz
  if [ $? -eq 0 ] ; then
    tar xzf redmine.tgz &&
    if [ $? -eq 0 ] ; then
      mv redmine-2.5.1 redmine
      if [ $? -ne 0 ] ; then
        echo "Impossible de renomer le dossier d'installation"
        return 1
      fi
    else
      echo "Impossible de décompresser l'archive."
      return 1
    fi
  else
    echo "Impossible de télécharger l'archive sur http://www.redmine.org"
    return 1
  fi
  return 0
}

function config_env_bash
{
  # Ajoute des variables d'environnement pour l'instance d'exécution

  local content="# rbenv - setting
PATH=\"\$HOME/.rbenv/versions/1.9.3-p194/bin:\$PATH\"
export PATH
# to detect .rbenv-version
eval \"\$(rbenv init -)\"

# prod
RAILS_ENV=\"$redmine_env\"
export RAILS_ENV" 
  echo "$content" >> ~/.bashrc
  # chargement de l'environement
  source ~/.bashrc
  
}

function config_database_connection
{
  # Crée le fichier de configuration des paramètres de connexion à la base
  # de données de l'instance.

  cd $HOME/redmine/
  config_file_database="$HOME/redmine/config/database.yml"
  touch $config_file_database
  local content="$redmine_env:
  adapter: $db_adapter
  database: $db_name
  host: $db_host
  username: $db_user
  password: $db_user_password"
  echo "$content" >> $config_file_database
}

function install_redmine
{
  # Installe l'application et ses dépendances dans un environnement ruby local

  function install_ruby
  {
    # Installe localement l'environnement ruby recommandé

    rbenv install 1.9.3-p194 && return 0 || return 1
  }

  function install_gems
  {
    # Installe les gems ruby (prérequis)

    gem install pg -v '0.17.1'
    gem install bundler
    gem install json -v '1.8.1'
    # gem install rdoc-data
    # rdoc-data --install
  }

  function install_bundles
  {
    # Configure et initialise l'application

    bundle install --without development test rmagick
    bundle exec rake db:migrate
    bundle exec rake generate_secret_token &&
    REDMIN_LANG=fr bundle exec rake redmine:load_default_data
  }

  cd $HOME/redmine
  install_ruby
  # Mise en place de l'environnement ruby local de l'instance d'exécution
  rbenv local 1.9.3-p194
  install_gems
  install_bundles 
}

function create_file_start
{
  # Crée le fichier de lancement de l'application

  # Définition du contenu du fichier
  local content="#!/bin/bash
# start_redmine.sh, place this inside your redmine-folder
RAILS_ENV='${redmine_env}'
export RAILS_ENV
pid='tmp/pids/server.pid'
# ok, this is hard now
if [ -f \$pid ]; then
  echo '> killing old instance'
  kill -TERM \"cat \$pid\"
  rm \$pid
fi
bundle exec ruby script/rails server webrick -e production -b ${redmine_ip} \
-p ${redmine_port} -d > redmine.log"

  # Création du fichier
  echo "${content}" > start_redmine_${USER}.sh
  chmod +x start_redmine_${USER}.sh
}

function create_redmine_user
{
  # Crée l'instance / le compte système d'exécution de l'application

  # Le compte d'instance ne doit pas être root
  id $redmine_user
  [ $? -ne 0 ] &&
  [ $UID -eq 0 ] && [ $redmine_user != "root" ] &&
  adduser --disabled-password --shell='/bin/bash' $redmine_user
}

function export_function
{
  # Exporte les fonctions autorisées

  for i in "${function_export[@]}"
  do
     export -f $i
  done  
}

function installation
{
  # Lance l'installation de l'application
  # Dépendances :
  #   - Fonctions : install_dependances, install_postgresql-client,
  #                 create_redmine_user,config_proxy, wget_redmine,
  #                 config_env_bash, config_database_connection,
  #                 manage_database, install_redmine, create_file_start,
  #                 reset_proxy

  # Première phase en tant que root
  if [ $UID -ne 0 ] ; then
    echo "Vous devez commencez l'installation en tant que root."
    su root
  fi
  install_dependances &&
  install_postgresql-client &&
  create_redmine_user
  # Deuxième phase dans l'env. utilisateur
  cd /home/${redmine_user}
  su ${redmine_user} -c config_proxy
  su ${redmine_user} -c wget_redmine
  su ${redmine_user} -c config_env_bash
  su ${redmine_user} -c config_database_connection
  su ${redmine_user} -c manage_database
  su ${redmine_user} -c source ~/.bashrc
  su ${redmine_user} -c install_redmine
  su ${redmine_user} -c create_file_start
  su ${redmine_user} -c reset_proxy
  cd ~
}

function __init_var
{
  # Initialise les variables globales de travail

  # Export et initialisation des variables globales
  export proxy_url=''
  export redmine_env='production'
  export redmine_user="${USER}"
  export db_adapter='postgresql'
  export db_name="redmine_${USER}"
  export db_host='localhost'
  export redmine_ip='127.0.0.1'
  export redmine_port='3000'
  export db_user="$USER"
  export db_user_password='azerty'
  export db_postgres_password=''
  # Liste des fonctions autorisées à l'export
  function_export=("config_poxy" "wget_redmine" "config_database_connection" \
  "manage_database" "install_redmine" "create_file_start" "reset_proxy")
}

function installation_menu
{
  # Menu d'installation de l'application
  # Définit les propriétés de l'installation et de l'applications

  local opt1="Chaîne de connexion Proxy  => $proxy_url"
  local opt2="Environement d'éxecution   => $redmine_env"
  local opt3="Compte d'instance redmine  => $redmine_user"
  local opt4="Hôte de la base de données => $db_host"
  local opt5="Nom de la Base de Données  => $db_name"
  local opt6="Nom du compte de la BD     => $db_user"
  local opt7="Mot de passe du compte     => $db_user_password"
  local opt8="Mot de passe de 'postgres' => $db_postgres_password"
  local opt9="Port web de l'application  => $redmine_port"
  local opt10="IP de l'application       => $redmine_ip"
  local opt11="Lancer l'installation."
  local opt12="Abandonner."
  local menuPrincipal=("$opt1" "$opt2" "$opt3" "$opt4" "$opt5" "$opt6" "$opt7" \
  "$opt8" "$opt9" "$opt10" "$opt11" "$opt12")
  
  select principal in "${menuPrincipal[@]}"
  do
    case $principal in
      "$opt1" ) echo -n "Entrez l'URL du proxy : " &&
                read proxy_url && return 0 ;;
      "$opt2" ) echo -n "Définissez le nom de l'environnement d'exécution : " &&
                read redmine_env && return 0 ;;
      "$opt3" ) echo -n "Définissez / donnez le compte d'instance redmine : " &&
                read redmine_user && return 0 ;;
      "$opt4" ) echo -n "Donnez le FQDN ou l'IP du serveur de base de données : " &&
                read db_host && return 0 ;;
      "$opt5" ) echo -n "Définissez le nom de la Base de Données : " &&
                read db_name && return 0 ;;
      "$opt6" ) echo -n "Définissez le nom du compte de gestion de la BD : " &&
                read db_user && return 0 ;;
      "$opt7" ) echo -n "Définisser le mot de passe du compte ${db_user} : " &&
                read db_user_password && return 0 ;;
      "$opt8" ) echo -n "Donnez le mot de passe du compte 'postgres' : " &&
                read db_postgres_password && return 0 ;;
      "$opt9" ) echo -n "Définissez le port web de l'application (3000-3333) : " &&
                read redmine_port && return 0 ;;
      "$opt10" ) echo -n "Définissez l'ip DE l'application : " &&
                 read redmine_ip && return 0 ;;
      "$opt11" ) installation && return 0 ;;
      "$opt12" ) return 1 ;;
    esac
  done
}

function mode_selection
{
  # Définit le mode d'installation de l'application (Interactif ; Direct)
  # Dépendances :
  #   - Fonctions : installation_menu, installation

  # Initialisation des variables locales
  local _interMode=0
  local _directMode=0
  
  # Parcours des options de la ligne de commande
  OPTIND=0
  while getopts ":P:e:r:a:n:h:u:w:W:p:l:iH-:" opt ; do
    case $opt in
      P ) proxy_url=$OPTARG ;;
      e ) redmine_env=$OPTARG ;;
      r ) redmine_user=$OPTARG ;;
      a ) db_adapter=$OPTARG ;;
      n ) db_name=$OPTARG ;;
      h ) db_host=$OPTARG ;;
      u ) db_user=$OPTARG ;;
      w ) db_user_password=$OPTARG ;;
      W ) db_postgres_password=$OPTARG ;;
      p ) redmine_port=$OPTARG ;;
      l ) redmine_ip=$OPTARG ;;
      i ) _interMode=1 ; echo 'mode interactif' ;;
      H ) _help=1 ;;
    esac
  done
  shift $((OPTIND-1))
  ### Lancement
  if [ $_interMode = 1 ] ; then
    while true; do
      installation_menu
      [ $? -ne 0 ] && break
    done
  fi
  [ $_interMode = 0 ] && _directMode=1
  [ $_directMode = 1 ] &&
  {
    [ $db_postgres_password ] && [ $redmine_user ] &&
    [ $proxy_url ] && [ $redmine_env ] && [ $db_adapter ] && [ $db_name ] &&
    [ $db_host ] && [ $db_user ] && [ $db_user_password ] &&
    (installation && return 0 || return 1)
  }
}
__init_var
mode_selection $@
