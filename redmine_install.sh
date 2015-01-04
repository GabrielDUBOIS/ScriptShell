#! /bin/bash

function install_dependances
{
  # Installation des dépendances sous Debian Wheezy
  clear
  local log='install_dependances.log'
  touch $log
  # Mise à jour de la distribution
  echo "Mise à jour de la distribution. Journal des erreurs => ${log}"
  (apt-get update && apt-get upgrade -y) 2> $log
  
  for package in ${wheezy_dep[@]} ; do
    # on vérifie préalablement la présence du paquet sur le système
    dpkg --list ${package} 2> $log
    # on installe après une simulation et s'il est absent du système
    if [ $? = 1 ] ; then
      echo "Installation du paquet ${package}. Journal des erreurs => ${log}"
      (apt-get install -ys ${package} && apt-get install -y) 2>> $log
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
  clear
  local log='install_postgresql-client.log'
  # on vérifie préalablement sa présence
  dpkg --list postresql-client > /dev/null 2> $log
  echo "Installation du client postgresql. Journal des erreurs => ${log}"
  [ $? = 1 ] && apt-get install -y postgresql-client 2> $log
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
  clear
  log='manage_database.log'
  msg="Création du compte et de sa base de données. Appel du script pgmanage.sh"
  msg+="Journal des erreurs => ${log}"
  echo  $msg
  echo $PATH_pgManage
  if [ -e "$PATH_pgManage" ] ; then 
    $PATH_pgManage -h ${db_host[1]} -p 5432 -U ${db_admin[1]} \
    -W ${db_admin_password[1]} -d ${db_name[1]} -u ${db_user[1]} \
    -w ${db_user_password[1]} 'check_user' 'check_db' 2> $log
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
    export http_proxy=${proxy_url[1]}
    export https_proxy=${proxy_url[1]}
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
  clear
  local log='wget_redmine.log'
  cd /$HOME
  echo "Téléchargement de redmine-${version}. Journal des erreurs => ${log}"
  wget -O redmine.tgz http://www.redmine.org/releases/redmine-${version}.tar.gz\
  2> $log
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
  clear
  local conf="\n# rbenv - setting"
  conf+="\nPATH=\$HOME/.rbenv/versions/${rbenv_version}/bin:\$PATH"
  conf+="\nexport PATH"
  conf+="\n# to detect .rbenv-version"
  conf+="\neval '\$(rbenv init -)'"
  conf+="\nRAILS_ENV='${redmine_env[1]}'"
  conf+="\export RAILS_ENV"
  echo "Modification du fichier ~/.bashrc"
  echo -e "${conf}" >> ~/.bashrc
  # chargement de l'environement
  source ~/.bashrc
}

function config_database_connection
{
  # Crée le fichier de configuration des paramètres de connexion à la base
  # de données de l'instance.
  clear
  cd ${HOME}
  config_file_database="$HOME/redmine/config/database.yml"
  echo "Configuration de la connexion à la base de données"
  echo "Création du fichier ${config_file_database}"
  touch $config_file_database
  local conf="\n${redmine_env[1]}:"
  conf+="\n  adapter: ${db_adapter[1]}"
  conf+="\n  database: ${db_name[1]}"
  conf+="\n  host: ${db_host[1]}"
  conf+="\n  username: ${db_user[1]}"
  conf+="\n  password: ${db_user_password[1]}"
  echo -e "${conf}" >> ${config_file_database}
}

function install_redmine
{
  # Installe l'application et ses dépendances dans un environnement ruby local

  function install_ruby
  {
    # Installe localement l'environnement ruby recommandé
    echo "Installation de l'environnement ruby (${rbenv_version})."
    rbenv install ${rbenv_version} > /dev/null 2> $log \
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
  clear
  local log='install_redmine.log'
  echo "Installation de l'environnement et des composants."
  echo "Journal des erreurs => ${log}"
  cd $HOME
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
  local conf="#!/bin/bash"
  conf+="\n# start_redmine.sh, place this inside your redmine-folder"
  conf+="\nRAILS_ENV='${redmine_env[1]}'"
  conf+="\nexport RAILS_ENV"
  conf+="\npid='tmp/pids/server.pid'"
  conf+="\n# ok, this is hard now"
  conf+="\nif [ -f \$pid ]; then"
  conf+="\n  echo '> killing old instance'"
  conf+="\n  kill -TERM \"cat \$pid\""
  conf+="\n  rm \$pid"
  conf+="\nfi"
  conf+="\nbundle exec ruby script/rails server webrick -e ${redmine_env[1]} "
  conf+="-b ${redmine_host[1]}} -p ${redmine_port[1]}} -d > redmine.log"

  # Création du fichier
  file_start=start_redmine_${redmine_user[1]}.sh
  echo "Création du fichier de démarrage => ${file_start}"
  echo -e "${conf}" > $file_start
  chmod +x file_start
}

function create_redmine_user
{
  # Crée l'instance / le compte système d'exécution de l'application
  clear
  local log='create_redmine_user.log'
  echo -n "Création du compte système ${redmine_user[1]}. "
  echo "Journal des erreurs ${log}"
  # Le compte d'instance ne doit pas être root
  id ${redmine_user[1]}
  [ $? -ne 0 ] &&
  [ $UID -eq 0 ] && [ ${redmine_user[1]} != "root" ] &&
  adduser --disabled-password --shell='/bin/bash' ${redmine_user[1]} 2> $log
  [ $? = 1 ] && return 1
  rm $log
  return 0
}

## GESTION DU MODE DIRECT ##

function direct_mode
{
  # Exécute les commandes passées en argument au regard des options

  _error=0
  # Teste si les informations de connexion au SGDB sont définies
  if [ "${db_host[1]}" = "${noDefine}" ] ||
  [ "${db_admin_password[1]}" = "${noDefine}" ]
  then
    msg="\nL'hôte du SGDB et le mot passe du compte ${db_admin[1]} "
    msg+="doivent être définis !\n"
    return 1
  fi
  echo "Ensemble des paramètres $@" ; read
  # Exécute les commandes passées en arguments
  echo "fonctions $@" ; read
  for cmd in $@ ; do
    echo "fonction $cmd" ; read
    # Vérifier que la méthode appelée est autorisée
    for c in "${direct_function[@]}" ; do
      
      if [ $cmd = $c ] ; then
        _error=0
        break
      else
        _error=1
      fi
    done
    if [ "${_error}" = 0 ] ; then
      # Exécution de la méthode autorisée
      eval "${cmd}"
    fi
    [ "${_error}" = 1 ] &&
    echo "Le méthode '${cmd}' est non autorisée en mode direct." &&
    return 1
  done
  return 0
}

function installation
{
  # Lance l'installation de l'application
  # Dépendances :
  #   - Fonctions : install_dependances, install_postgresql-client,
  #                 create_redmine_user, direct_mode, $direct_function

  if [ "${USER}" = root ] ; then
    # Première phase en tant que root
    echo "Lancement de l'installation sous le compte root."
    # install_dependances &&
    # install_postgresql-client &&
    create_redmine_user
    manage_database
    # Deuxième phase dans l'environement du compte redmine_user
    echo "Poursuite de l'installation sous le compte ${redmine_user[1]}"
    cd /home/${redmine_user[1]}
    # Préparation des options à passer dans l'appel récursif du script
    [ ${proxy_url[1]} ] && OPTS="-P ${proxy_url[1]} " || OPTS=""
    OPTS+="-e ${redmine_env[1]} -r ${redmine_user[1]} "
    OPTS+="-s ${redmine_port[1]} -t ${redmine_host[1]} -a ${db_adapter[1]} "
    OPTS+="-d ${db_name[1]} -h ${db_host[1]} -p ${db_port[1]} "
    OPTS+="-u ${db_user[1]} -w ${db_user_password[1]} "
    OPTS+="-U ${db_admin[1]} -W ${db_admin_password[1]}"
    # Préparation des arguments à passer dans l'appel récursif du script
    ARGS=${direct_function[@]}
    # Appel récursif au script sous le compte redmine_user
    echo "options arguments : su ${redmine_user[1]} -c ${0} ${OPTS} ${ARGS}" ; read
    su ${redmine_user[1]} -c "${PATH_THIS} ${OPTS} ${ARGS}" 2> error.log
  elif [ "${USER}" = "${redmine_user[1]}" ] ; then
    echo "Deuxième phase d'installation dans le mode direct récursif" ; read
    # Deuxième phase d'installation dans le mode direct récursif
    direct_mode $@
  else
    echo "Compte utilisateur ${redmine_user[1]} non autorisé à lancer le script."
    return 1
  fi
  
  # su ${redmine_user[1]} -c config_proxy
  # su ${redmine_user[1]} -c wget_redmine
  # su ${redmine_user[1]} -c config_env_bash
  # su ${redmine_user[1]} -c config_database_connection
  # su ${redmine_user[1]} -c manage_database
  # su ${redmine_user[1]} -c source ~/.bashrc
  # su ${redmine_user[1]} -c install_redmine
  # su ${redmine_user[1]} -c create_file_start
  # su ${redmine_user[1]} -c reset_proxy

  # retour dans l'environnement root
  cd ~
}

function __init_var
{
  # Initialise les variables globales
  PATH_THIS=/opt/${0#./}
  PATH_pgManage=/opt/pgmanage.sh
  # Export et initialisation des variables globales
  noDefine='Non Défini'
  proxy_url[1]=${proxy_url[0]:=''}
  redmine_env[1]=${redmine_env[0]:=$noDefine}
  redmine_user[1]=${redmine_user[0]:=$noDefine}
  redmine_host[1]=${redmine_host[0]:=$noDefine}
  redmine_port[1]=${redmine_port[0]:=$noDefine}
  db_adapter[1]=${db_adapter[0]:='postgresql'}
  db_name[1]=${db_name[0]:=$noDefine}
  db_host[1]=${db_host[0]:=$noDefine}
  db_port[1]=${db_port[0]:='5432'}
  db_user[1]=${db_user[0]:=$noDefine}
  db_user_password[1]=${db_user_password[0]:=$noDefine}
  db_admin[1]=${db_admin[0]:=$noDefine}
  db_admin_password[1]=${db_admin_password[0]:=$noDefine}
  TEST[1]=${TEST[0]:=false} # Lancement en mode DEBUG et VERBOSE
  _exit=0     # sortie de script
  
  # Liste des fonctions autorisées en mode direct
  direct_function=("config_proxy" "wget_redmine" "config_database_connection" \
  "config_env_bash" "install_redmine" "create_file_start" \
  "reset_proxy")
  
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

## GESTION DU MODE INTERACTIF ##

function installation_menu
{
  # Menu d'installation de l'application
  # Définit les propriétés de l'installation et de l'applications

  clear

  local opt1="Chaîne de connexion au Proxy          => ${proxy_url[1]},"
  local opt2="Environement d'éxecution  redmine     => ${redmine_env[1]}",
  local opt3="Compte système de l'instance redmine  => ${redmine_user[1]},"
  local opt4="URI de l'hôte de la base de données   => ${db_host[1]},"
  local opt5="Nom de la Base de Données             => ${db_name[1]},"
  local opt6="Nom du compte de la Base de Données   => ${db_user[1]},"
  local opt7="Mot de passe du compte                => ${db_user_password[1]},"
  local opt8="Compte d'administration ${db_adapter[1]}    => ${db_admin[1]},"
  local opt9="Mot de passe de ${db_admin[1]} => ${db_admin_password[1]},"
  local opt10="Port web de l'application  => ${redmine_port[1]},"
  local opt11="IP de l'application        => ${redmine_host[1]},"
  local opt12="Lancer l'installation,"
  local opt13="Réinitialiser les variables,"
  local opt14="Abandonner."
  local menuPrincipal=("$opt1" "$opt2" "$opt3" "$opt4" "$opt5" "$opt6" "$opt7" \
  "$opt8" "$opt9" "$opt10" "$opt11" "$opt12" "$opt13" "$opt14")
  
  select principal in "${menuPrincipal[@]}"
  do
    case $principal in
      "$opt1" ) 
        v=${proxy_url[1]}
        echo -n "Entrez l'URL du proxy (${v}): " ; read r
        proxy_url[1]=${r:=$v}
        return 0 ;;
      "$opt2" )
        v=${redmine_env[1]}
        echo -n "Définissez le nom de l'environnement d'exécution (${v}) : "
        read r
        redmine_env[1]=${r:=$v}  
        return 0 ;;
      "$opt3" )
        v=${redmine_user[1]}
        echo -n "Définissez / donnez le compte d'instance redmine (${v}) : "
        read r
        redmine_user[1]=${r:=v}
        return 0 ;;
      "$opt4" )
        v=${db_host[1]}
        echo -n "Donnez le FQDN ou l'IP du serveur de base de données (${v}) : "
        read r
        db_host[1]=${r:=$v}
        return 0 ;;
      "$opt5" )
        v=${db_name[1]}
        echo -n "Définissez le nom de la Base de Données (${v}) : "
        read  r
        db_name[1]=${r:=$v}
        return 0 ;;
      "$opt6" )
        v=${db_user[1]}
        echo -n "Définissez le nom du compte de gestion de la BD (${v}) : "
        read r
        db_user[1]=${r:=$v}
        return 0 ;;
      "$opt7" )
        v=${db_user_password[1]}
        echo -n "Définissez le mot de passe du compte ${db_user[1]} (${v}) : "
        read r
        db_user_password[1]=${r:=$v}
        return 0 ;;
      "$opt8" )
        v=${db_admin[1]}
        echo -n "Donnez le compte administrateur ${db_adapter[1]} (${v}) : "
        read r
        db_admin[1]=${r:=$v}
        return 0 ;;
      "$opt9" )
        v=${db_admin_password[1]}
        echo -n "Donnez le mot de passe du compte ${db_admin[1]} (${v}) : "
        read r
        db_admin_password[1]=${r:=$v}
        return 0 ;;
      "$opt10" )
        v=${redmine_port[1]}
        echo -n "Définissez le port web de l'application [3000-3333] (${v}) : "
        read r
        redmine_port[1]=${r:=$v}
        return 0 ;;
      "$opt11" )
        r=${redmine_host[1]}
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
  while getopts ":P:e:r:s:t:a:d:h:p:u:w:U:W:TiH-:" opt ; do
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
      T ) TEST[0]=true
      H ) _help=1 ;;
    esac
  done
  shift $((OPTIND-1))

  # Mise à jour des variables globales de travail
  __init_var || return 1

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
    echo "Lancement du mode direct sous le compte ${USER}=${redmine_user[1]}" ; read
    installation $@ || return 1
  fi
}
echo "Lancement du script sous le compte ${USER}" ; read
echo "Paramètres passés $@" ; read
execution_mode $@
