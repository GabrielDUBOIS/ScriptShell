#! /bin/bash

function install_dependances
{
  # Installation des dépendances sous Debian Wheezy
  
  local log='install_dependances.log'
  touch $log
  # Mise à jour de la distribution
  echo "Mise à jour de la distribution. Journal des erreurs => ${log}"
  (apt-get update && apt-get upgrade -y) > /dev/null 2> $log
  
  for package in ${wheezy_dep[@]} ; do
    # on vérifie préalablement la présence du paquet sur le système
    dpkg --list ${package} > /dev/null 2> $log
    # on installe après une simulation et s'il est absent du système
    if [ $? = 1 ] ; then
      echo "Installation du paquet ${package}. Journal des erreurs => ${log}"
      (apt-get install -ys ${package} && apt-get install -y) > /dev/null 2>> $log
      [ $? = 1 ] && (echo "Erreur lors de l'installation." ; return 1)
    fi
  done
  echo "Installation des dépendances réussie. Effacement du journal ${log}"
  rm $log
  return 0
}

function install_postgresql-client
{
  # Installation du client de postgresql sous Debian Wheezy
  
  local log='install_postgresql-client.log'
  # on vérifie préalablement sa présence
  dpkg --list postresql-client > /dev/null 2> $log
  echo "Installation du client postgresql. Journal des erreurs => ${log}"
  [ $? = 1 ] && apt-get install -y postgresql-client > /dev/null 2> $log
  [ $? = 1 ] && (echo "Erreur lors de l'installation." ; return 1)
  echo "Installation réussie. Effacement du journal ${log}"
  rm $log
  return 0
}

function manage_database
{
  # Lance le script de gestion des comptes et bases de données
  # Dépendance :
  #   - Script : ./pgmanage.sh

  log='manage_database.log'
  msg="Création du compte et de sa base de données. Appel du script pgmanage.sh"
  msg+="Journal des erreurs => ${log}"
  echo  $msg
  if [ -e './pgmanage.sh' ] ; then 
    ./pgmanage.sh -h ${db_host[1]} -p 5432 -U ${admin_db[1]} \
    -W ${db_admin_password[1]} -d ${db_name[1]} -u ${db_user[1]} \
    -w ${db_user_password[1]} check_user check_db 2> $log
    [ $? = 1 ] && (echo "Erreur lors du processus." ; return 1)
    echo "Installation réussie. Effacement du journal ${log}"
    rm $log
    return 0
  else
    echo "Le script './pgmanage.sh' n'est pas présent. Arrêt du processus."
    return 1
  fi
}

function config_proxy
{
  # Configure le proxy
  
  echo "Configuration du proxy path"
  if [ $proxy_url[1] ] ; then
    export http_proxy=$proxy_url[1]
    export https_proxy=$proxy_url[1]
  fi
}

function reset_proxy
{
  # Réinitialise le proxy
  
  echo "Réinitialisation du proxy"
  export http_proxy=''
  export https_proxy=''
}

function wget_redmine
{
  # Récupère, décompresse et renomme l'archive de l'application

  local log='wget_redmine.log'
  cd /$HOME
  echo "Téléchargement de redmine-${version}. Journal des erreurs => ${log}""
  wget -O redmine.tgz http://www.redmine.org/releases/redmine-${version}.tar.gz\
  > /dev/null 2> $log
  if [ $? -eq 0 ] ; then
    echo "Décompression de l'archive."
    tar xzf redmine.tgz  > /dev/null 2> $log
    if [ $? -eq 0 ] ; then
      echo "Dossier de destination => ./redimine"
      mv redmine-${version} redmine  > /dev/null 2> $log
      if [ $? -ne 0 ] ; then
        echo "Impossible de renommer le dossier d'installation"
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
  rm $log
  return 0
}

function config_env_bash
{
  # Ajoute des variables d'environnement pour l'instance d'exécution
  
  echo "Modification du fichier ~/.bashrc"
  local content="# rbenv - setting
PATH=\"\$HOME/.rbenv/versions/${rbenv_version}/bin:\$PATH\"
export PATH
# to detect .rbenv-version
eval \"\$(rbenv init -)\"

# prod
RAILS_ENV=\"${redmine_env[1]}\"
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
  echo "Configuration de la connexion à la base de données"
  echo "Création du fichier ${config_file_database}"
  touch $config_file_database
  local content="${redmine_env[1]}:
  adapter: ${db_adapter[1]}
  database: ${db_name[1]}
  host: ${db_host[1]}
  username: ${db_user[1]}
  password: ${db_user_password[1]}"
  echo "$content" >> $config_file_database
}

function install_redmine
{
  # Installe l'application et ses dépendances dans un environnement ruby local
  
  function install_ruby
  {
    # Installe localement l'environnement ruby recommandé
    echo "Installation de l'environnement ruby (${rbenv_version})."
    rbenv install ${rbenv_version} > /dev/null 2> $log
    && return 0 || return 1
  }

  function install_gems
  {
    # Installe les gems ruby (prérequis)
    echo "Installation des gems ruby."
    gem install pg -v '0.17.1' > /dev/null 2> $log
    [ $? = 1 ] && return 1
    gem install bundler > /dev/null 2> $log
    [ $? = 1 ] && return 1
    gem install json -v '1.8.1' > /dev/null 2> $log
    [ $? = 1 ] && return 1
    return 0
  }

  function install_bundles
  {
    # Configure et initialise l'application
    # installation des bundles redmine
    bundle install --without development test rmagick > /dev/null 2> $log
    [ $? = 1 ] && return 1
    echo -e "\tInitialisation de la base de données."
    bundle exec rake db:migrate > /dev/null 2> $log
    [ $? = 1 ] && return 1
    echo -e "\tGénération de la clé sercête."
    bundle exec rake generate_secret_token > /dev/null 2> $log
    [ $? = 1 ] && return 1
    echo -e "\tInitialisation des locales"
    REDMIN_LANG=fr bundle exec rake redmine:load_default_data \
    > /dev/null 2> $log
    [ $? = 1 ] && return 1
    return 0
  }
  
  local log='install_redmine.log'
  echo "Installation de l'environnement et des composants.
  echo "Journal des erreurs => ${log}"
  cd $HOME/$[redmine_user[1]}
  install_ruby || return 1
  echo "Initialisation de l'environnement ruby locale" 
rbenv local ${rbenv_version} || return 1
  install_gems || return 1
  install_bundles  || return 1
  rm $log
}

function create_file_start
{
  # Crée le fichier de lancement de l'application
  
  # Définition du contenu du fichier
  local content="#!/bin/bash
# start_redmine.sh, place this inside your redmine-folder
RAILS_ENV='${redmine_env[1]}'
export RAILS_ENV
pid='tmp/pids/server.pid'
# ok, this is hard now
if [ -f \$pid ]; then
  echo '> killing old instance'
  kill -TERM \"cat \$pid\"
  rm \$pid
fi
bundle exec ruby script/rails server webrick -e ${redmine_env[1]} \
-b ${redmine_host[1]}} -p ${redmine_port[1]}} -d > redmine.log"

  # Création du fichier
  file_start=start_redmine_$[redmine_user[1]}.sh
  echo "Création du fichier de démarrage => ${file_start}"
  echo "${content}" > $file_start
  chmod +x file_start
}

function create_redmine_user
{
  # Crée l'instance / le compte système d'exécution de l'application

  local log='create_redmine_user.log'
  echo -n "Création du compte système ${redmine_user[1]}. "
  echo "Journal des erreurs ${log}"
  # Le compte d'instance ne doit pas être root
  id ${redmine_user[1]}
  [ $? -ne 0 ] &&
  [ $UID -eq 0 ] && [ ${redmine_user[1]} != "root" ] &&
  adduser --disabled-password --shell='/bin/bash' ${redmine_user[1]} \
  > /dev/null 2> $log
  [ $? = 1 ] && return 1
  rm $log
  return 0
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
  #                 reset_proxy, export_function

  # Première phase en tant que root
  if [ $UID -ne 0 ] ; then
    echo "Vous devez commencez l'installation en tant que root."
    su root
  fi
  
  echo "Lancement de l'installation sous le compte root."
  install_dependances &&
  install_postgresql-client &&
  create_redmine_user
  
  # Deuxième phase
  # Exportation des fonctions
  export_function
  # Placement dans l'environement utilisateur
  echo "Poursuite de l'installation sous le compte ${redmine_user[1]}"
  cd /home/${redmine_user}
  su ${redmine_user[1]} -c config_proxy
  su ${redmine_user[1]} -c wget_redmine
  su ${redmine_user[1]} -c config_env_bash
  su ${redmine_user[1]} -c config_database_connection
  su ${redmine_user[1]} -c manage_database
  su ${redmine_user[1]} -c source ~/.bashrc
  su ${redmine_user[1]} -c install_redmine
  su ${redmine_user[1]} -c create_file_start
  su ${redmine_user[1]} -c reset_proxy
  cd ~
}

function __init_var
{
  # Initialise les variables globales

  # Export et initialisation des variables globales
  noDefine='Non Défini'
  export proxy_url[1]=${proxy_url[0]:=$noDefine}
  export redmine_env[1]=${redmine_env[0]:=$noDefine}
  export redmine_user[1]=${redmine_user[0]:=$noDefine}"
  export redmine_host[1]=${redmine_host[1]:=$noDefine}
  export redmine_port[1]=${redmine_port[0]:=$noDefine}
  export db_adapter[1]=${db_adaptater[0]:=$noDefine}
  export db_name[1]=${db_name[0]:=$noDefine}
  export db_host[1]=${db_host[0]:=$noDefine}
  export db_port[1]=${db_port[0]:=$noDefine}
  export db_user[1]=${db_user[0]:=:=$noDefine}
  export db_user_password[1]=${db_user_password[0]:=$noDefine}
  export db_admin[1]=${db_admin[0]:=:=$noDefine}
  export db_admin_password[1]=${db_admin_password[0]:=$noDefine}
  _exit=0     # sortie de script

  # Liste des fonctions autorisées à l'export
  function_export=("config_poxy" "wget_redmine" "config_database_connection" \
  "manage_database" "install_redmine" "create_file_start" "reset_proxy")
  
  # Liste des dépendances sous Debian wheezy
  wheezy_dep=("build-essential" "bison" "openssl" "curl" "git-core" "zlib1g" \
  "zlib1g-dev" "screen" "libruby" "libcurl4-openssl-dev" "libssl-dev" \
  "libmysqlclient-dev" "libxml2-dev" "libmagickwand-dev" "libpq5" "libpq-dev" \
  "rbenv" "ruby-build" "ruby-dev")
  
  # Environnement Ruby
  export rbenv_version='1.9.3-p194'
  
  # Environenment redmine
  export version='2.5.1'
}

function installation_menu
{
  # Menu d'installation de l'application
  # Définit les propriétés de l'installation et de l'applications

  clear

  local opt1="Chaîne de connexion Proxy  => $proxy_url[1],"
  local opt2="Environement d'éxecution   => $redmine_env[1]",
  local opt3="Compte d'instance redmine  => $redmine_user[1],"
  local opt4="Hôte de la base de données => $db_host[1],"
  local opt5="Nom de la Base de Données  => $db_name[1],"
  local opt6="Nom du compte de la BD     => $db_user[1],"
  local opt7="Mot de passe du compte     => $db_user_password[1],"
  local opt8="Compte d'administration ${db_adapter[1]}    => $db_admin[1],"
  local opt9="Mot de passe de ${db_admin[1]} => $db_admin_password[1],"
  local opt10="Port web de l'application  => $redmine_port[1],"
  local opt11="IP de l'application       => $redmine_host[1],"
  local opt12="Lancer l'installation,"
  local opt13="Réinitialiser les variables,"
  local opt14="Abandonner."
  local menuPrincipal=("$opt1" "$opt2" "$opt3" "$opt4" "$opt5" "$opt6" "$opt7" \
  "$opt8" "$opt9" "$opt10" "$opt11" "$opt12" "$opt13" "$top14")
  
  select principal in "${menuPrincipal[@]}"
  do
    case $principal in
      "$opt1" ) 
        v=${proxy_url[1]}
        echo -n "Entrez l'URL du proxy (${v}): " ; read r
        proxy_url[1]=${r:=$v}
        return 0 ;;
      "$opt2" )
        v=$redmine_env[1]
        echo -n "Définissez le nom de l'environnement d'exécution (${v}) : "
        read r
        redmine_env[1]=${r:=$v}  
        return 0 ;;
      "$opt3" )
        v=$redmine_user[1]
        echo -n "Définissez / donnez le compte d'instance redmine (${v}) : "
        read r
        redmine_user[1]=${r:=v}
        return 0 ;;
      "$opt4" )
        v=$db_host[1]
        echo -n "Donnez le FQDN ou l'IP du serveur de base de données (${v}) : "
        read r
        db_host[1]=${r:=$v}
        return 0 ;;
      "$opt5" )
        v=$db_name[1]
        echo -n "Définissez le nom de la Base de Données (${v}) : "
        read  r
        db_name=${r:=$v}
        return 0 ;;
      "$opt6" )
        v=$db_user[1]
        echo -n "Définissez le nom du compte de gestion de la BD (${v}) : "
        read r
        db_user[1]=${r:=$v}
        return 0 ;;
      "$opt7" )
        v=$db_user_password[1]
        echo -n "Définisser le mot de passe du compte ${db_user} (${v}) : "
        read r
        db_user_password[1]=${r:=$v}
        return 0 ;;
      "$opt8" )
        v=$db_admin[1]
        echo -n "Donnez le compte administrateur ${db_adapter} (${v}) : "
        read r
        db_admin[1]=${r:=$v}
        return 0 ;;
      "$opt9" )
        v=$db_admin_password[1]
        echo -n "Donnez le mot de passe du compte ${db_admin} (${v}) : " &&
        read r
        db_admin_password[1]=${r:=$v}
        return 0 ;;
      "$opt10" )
        v=$redmine_port[1]
        echo -n "Définissez le port web de l'application [3000-3333] (${v}) : "
        read r
        redmine_port[1]=${r:=$v}
        return 0 ;;
      "$opt11" )
        r=$redmine_host[1]
        echo -n "Définissez l'IP de l'application (${v}) : "
        read r
        redmine_host[1]=${r:=$v}
        return 0 ;;
      "$opt12" ) 
        installation && return 0 || return 1 ;;
      "$opt13" )
        __init_var && return 0 || return 1 ;;
      "$opt14" )
        _exit=1 ; return 0 ;;
    esac
  done
}

function execution_mode
{
  # Déterline le mode d'installation de l'application (Interactif ; Direct)
  # Dépendances :
  #   - Fonctions : installation_menu, installation

  # Initialisation des variables
  __init_var
  local _interMode=0
  local _directMode=0
  local _help=0
  
  # Traitement des options de la ligne de commande
  OPTIND=0
  while getopts ":P:e:r:s:a:d:h:p:u:w:U:W:iH-:" opt ; do
    case $opt in
      P ) proxy_url[0]=$OPTARG ;;
      e ) redmine_env[0]=$OPTARG ;;
      r ) redmine_user[0]=$OPTARG ;;
      s ) redmine_port[0]=$OPTARG ;;
      t ) redmine_host[0]=$OPTARG ;;
      a ) db_adapter[0]=$OPTARG ;;
      d ) db_name[0]=$OPTARG ;;
      h ) db_host[0]=$OPTARG ;;
      p ) db_port[0]=$OPTARG ;;
      u ) db_user[0]=$OPTARG ;;
      w ) db_user_password[0]=$OPTARG ;;
      U ) db_admin[0]=$OPTARG ;;
      W ) db_admin_password[0]=$OPTARG ;;
      i ) _interMode=1 ; echo 'Mode interactif' ;;
      H ) _help=1 ;;
    esac
  done
  shift $((OPTIND-1))

  ### Sélection du mode
  if [ $_interMode = 1 ] ; then
    while true; do
      installation_menu
      [ $? -ne 0 ] && return 1
      [ $_exit = 1 ] && break
    done
  else
    _directMode=1
  fi
  # Demande d'installation directe ?
  if [ $_directMode = 1 ] ; then
    [ "${db_admin_password[0]}" ] && [ "${redmine_user[0]}" ] &&
    [ "${redmine_env[0]}" ] && [ "${db_adapter[0]}" ] && [ "${db_name[0]}" ] &&
    [ "${db_host[0]}" ] && [ "${db_user[0]}" ] && [ "${db_user_password[0]}" ]\
    && installation || return 1
}

execution_mode $@
return 0
