#! /bin/bash

##                                     ##
# SCRIPT DE GESTION DE BASES DE DONNÉES #
# Description :                         #
##                                     ##

##                                                  ##
# FONCTIONS DE GESTION DES INFORMATIONS DE CONNEXION #
##                                                  ##
function set_pgpassfile
{ # Prépare le fichier de connexion .pgpass
  PGPASSFILE_OLD=$PGPASSFILE
  PGPASSFILE="$HOME/.pgpass"
  if [ -f ${PGPASSFILE} ] ; then
    mv ${PGPASSFILE} ${PGPASSFILE}.old    
  fi
  touch $PGPASSFILE
  chmod 0600 $PGPASSFILE
  export PGPASSFILE
  echo "${db_host[1]}:5432:*:postgres:${db_admin_password[1]}" > $PGPASSFILE
  return 0
}

function reset_pgpassfile
{ # restaure le fichier de connexion ou le supprime

  if [ -f ${PGPASSFILE}.old ] ; then
    mv ${PGPASSFILE}.old ${PGPASSFILE}
  else
    rm $PGPASSFILE
  fi
  PGPASSFILE=$PGPASSFILE_OLD
  return 0
}

##                                               ##
# FONCTIONS DE TRAITEMENT ET D'EXÉCUTION DE CODES #
##                                               ##
function sql_apply
{ # Applique le code SQL transmis en argument
  # Journalise les erreurs SQL
  # Dépendances :
  #   - Fonctions : set_pgpassfile, reset_pgpassfile

  set_pgpassfile 2>> ${archiveLog}
  # Instruction SQL PostgreSQL
  sql="${1}"
  # Requête sur le SGDB cible
  psql -h ${db_host[1]} -U ${db_admin[1]} -c "${sql}" 2> ${errorLog}
  [ $? -eq 1 ] && _error=1
  cat ${errorLog} >> ${archiveLog}
  reset_pgpassfile 2>> ${archiveLog}
  # Gestion d'exception
  [ $_error = 1 ] && return 1 || return 0
}

function manage_sql_error
{ # Affiche les erreurs rencontrées lors de la dernière exécution

  tail -n 2 ${errorLog}
  sql="\n#  => ${sql}\n#  => erreur lors de l'exécution"
  read ;
}

##                                             ##
# FONCTIONS DE GESTION DES COMPTES UTILISATEURS #
##                                             ##
function test_user_info
{ # Teste si les propriétées du compte utilisateur ont été définies

  if [ "${db_user[1]}" = "${noDefine}" ] ||
  ([ "${db_user_password[1]}" = "${noDefine}" ] && [ ${1} != DROP ])
  then
    msg="\nLe nom du compte et le mot de passe de l'utilisateur "
    msg+="doivent être définis !\n"
    echo -e "${msg}"
    return 1
  fi
  return 0
}

function test_user_exist
{ # Teste l'existance du compte utilisateur
  # Dépendances :
  #   - Fonctions : set_pgpassfile, reset_pgpassfile

  # Le compte existe t'il déjà ?
  declare -i i=0
  result_user=0
  set_pgpassfile  2>> ${archiveLog}
  # Requête sur l'existance du compte utilisateur
  sql="select count(*) from pg_user where usename='${db_user[1]}';"
  psql -h ${db_host[1]} -U ${db_admin[1]} -c "${sql}" > result.txt
  reset_pgpassfile 2>> ${archiveLog}
  # Analyse du résultat
  while read value
  do
    if [ $i -eq 2 ] ; then
      # Stockage du résultat
      result_user=$value
    fi
    i+=1
  done < result.txt
  rm result.txt
  # Retourne le résultat
  if [ $result_user = 0 ] ; then
    _error=1
    return 1
  fi
  return 0
}

function create_user
{ # Crée un compte utilisateur sur le SGDB cible
  # Dépendances :
  #   - Fonctions: test_user_info, sql_apply

  # Test de validité des arguments
  test_user_info || return 1
  # Instruction SQL PostgreSQL
  sql="CREATE ROLE \"${db_user[1]}\" WITH LOGIN ENCRYPTED PASSWORD "
  sql+="'${db_user_password[1]}' NOINHERIT VALID UNTIL 'infinity';"
  # Requête sur le SGDB cible
  sql_apply "${sql}" && return 0 || return 1
}

function alter_user_password
{ # Modifie le mot de passe du compte sur le SGDB cible
  # Dépendances :
  #   - Fonctions: test_user_info, sql_apply

  # Test de validité des arguments
  test_user_info || return 1
  # Instruction SQL PostgreSQL
  sql="ALTER USER \"${db_user[1]}\" WITH "
  sql+="LOGIN ENCRYPTED PASSWORD '${db_user_password[1]}';"
  # Requête sur le SGDB cible
  sql_apply "${sql}" && return 0 || return 1
}

function delete_user
{ # Supprime un compte utilisateur sur le SGDB cible
  # Dépendances :
  #   - Fonctions: test_user_info, sql_apply

  # Test de validité des arguments
  test_user_info DROP || return 1
  set_pgpassfile 2>> ${archiveLog}
  # Instruction SQL PostgreSQL
  sql="DROP ROLE \"${db_user[1]}\";"
  # Requête sur le SGDB cible
  sql_apply "${sql}" && return 0 || return 1
}

function check_user
{ # Gère le compte utilisateur sur le SGDB cible
  # Dépendances :
  #   - Fonctions: create_user, alter_user_pwd, delete_user

  # Le compte existe t'il déjà ?
  test_user_exist
  if [ $result_user = 0 ] ; then
    # Zéro compte db_user, donc le créer
    create_user && return 0
    return 1
  else
    # Le compte existe déjà, le recréer ?
    msg="Le compte utilisateur ${db_user[1]} existe déjà."
    msg+="voulez-vous le recréer ? (O/N/Y) : "
    echo -ne "${msg}"
    read r
    if [[ $r = [OYoy] ]] ; then
      # Si oui le recréer : suppression + création
      delete_user
      [ $? -eq 0 ] && create_user && return 0
      return 1
    elif [[ $r = [Nn] ]] ; then
      # Si non, changer son mot de passe ?
      msg="Voulez-vous mettre à jour le mot de passe de ${db_user[1]} ? (O/N/Y) :"
      echo -ne "${msg}"
      read r
      if [[ $r = [OYoy] ]] ; then
        # Si oui, mettre à jour le mot de passe
        alter_user_password && return 0
        read ; return 1
      elif [[ $r = [Nn] ]] ; then
        # Si non, ne rien faire
        return 0
      else
        # Réponse non prise en charge
        echo "Mauvaise réponse sur le changement de mot de passe."
        return 1
      fi
    else
      # Mauvaise réponse
      echo "Mauvaise réponse sur le recréation du compte ${db_user[1]}."
      return 1
    fi
  fi   
}

##                                         ##
# FONCTIONS DE GESTION DES BASES DE DONNÉES #
##                                         ##

function test_db_exist
{ # Teste l'existance de la base de données à gérer
  # Dépendances :
  #   - Fonctions : set_pgpassfile, reset_pgpassfile

  declare -i i=0
  result_db=0
  set_pgpassfile 2>> ${archiveLog}
  # Requête sur l'existance de la base de données
  sql="select count(*) from pg_database where datname='${db_name[1]}';"
  psql -h ${db_host[1]} -U ${db_admin[1]} -c "${sql}" > result.txt
  reset_pgpassfile 2>> ${archiveLog}
  while read value
  do
    if [ $i -eq 2 ] ; then
      # Stockage du résultat
      result_db=$value
    fi
    i+=1
  done < result.txt
  rm result.txt
  if [ $result_db = 0 ] ; then
    _error=1
    return 1
  fi
  return 0
}

function test_db_info
{ # Vérifie si les informattions du compte sont fournies

  # Test de validité des arguments
  if [ "${db_name[1]}" = "${noDefine}" ] ||
  ([ "${db_user[1]}" = "${noDefine}" ] && [ ${1} != DROP ])
  then
    msg="\nLe nom de la base de données et du propriétaire "
    msg+="doivent être définis !\n"
    echo -e "${msg}"
    return 1
  fi
  return 0
}

function create_db
{ # Crée une base de données avec le compte db_user pour propriétaire
  # sur le SGDB cible
  # Dépendances :
  #   - Fonctions : test_db_info, sql_apply

  test_db_info || return 1
  # Instruction SQL
  sql="CREATE DATABASE \"${db_name[1]}\" "
  sql+="WITH ENCODING='UTF8' OWNER=\"${db_user[1]}\";"
  # Requête sur le SGDB cible
  sql_apply "${sql}" && return 0 || return 1
}

function delete_db
{ # Supprime une base de données sur le SGDB cible
  # Dépendances :
  #   - Fonctions : test_db_info, sql_apply

  test_db_info DROP || return 1
  # Instruction SQL
  sql="DROP DATABASE \"${db_name[1]}\";"
  # Requête sur le SGDB cible
  sql_apply "${sql}" && return 0 || return 1
}

function alter_db_owner
{ # Modifie le propriétaire d'une base de données sur le SGDB cible
  # Dépendances :
  #   - Fonctions : test_db_info, sql_apply

  test_db_info || return 1
  # Instruction SQL
  sql="ALTER DATABASE \"${db_name[1]}\" OWNER TO \"${db_user[1]}\";"
  # Requête sur le SGDB cible
  sql_apply "${sql}" && return 0 || return 1
}

function check_db
{ # Gère la base de données sur le SGDB cible
  # Dépendances :
  #   - Fonctions: create_db, alter_db_owner, delete_db

  # La base existe t'elle déjà
  test_db_exist
  if [ $result_db = 0 ] ; then
    # Zéro base db_name, donc la créer
    create_db && return 0
    return 1
  else
    # La base existe déjà, la recréer ?
    msg="la base de données ${db_name[1]} existe déjà.\n"
    msg+="Voulez-vous la recréer ? (O/N/Y) : "
    echo -ne "$msg"
    read r
    if [[ $r = [OYoy] ]] ; then
      # Si oui la recréer : suppression + création
      delete_db
      [ $? -eq 0 ] && create_db && return 0
      msg="Impossible de supprimer la base de données ${db_name[1]}.\n"
      msg+="Abandon de la procédure."      
      echo -ne "${msg}"
      read ; return 1
    elif [[ $r = [Nn] ]] ; then 
      # Si non la conserver. Proposer changement de propriétaire.
      msg="Voulez-vous changer de propriétaire pour ${db_user[1]} ? (O/N/Y) : "
      echo -ne "${msg}"
      read r
      if [[ $r = [OYoy] ]] ; then
        # Si oui, changer de propriétaire
        alter_db_owner && return 0
        read ; return 1
      elif [[ $r = [Nn] ]] ; then
        # Si non ne rien faire
        return 0
      else
        # Réponse non prise en charge
        echo "Mauvaise réponse sur le changement de propriétaire ${db_user[1]}."
        return 1
      fi
    else
      # Mauvaise réponse
      echo "Mauvaise réponse sur la recréation de la base de données ${db_name[1]}."
      return 1
    fi
  fi    
}

##                              ##
# FONCTIONS DE GESTION DU SCRIPT #
##                              ##

function __init_var
{ # Initialise les variables globales de travail

  # Valeurs par default des propriétés
  noDefine='Non Défini'
  db_host[1]=${db_host[0]:=$noDefine}
  db_port[1]=${db_port[0]:='5432'}
  db_name[1]=${db_name[0]:=$noDefine}
  db_user[1]=${db_user[0]:=$noDefine}
  db_user_password[1]=${db_user_password[0]:=$noDefine}
  db_admin[1]=${db_admin[0]:='postgres'}
  db_admin_password[1]=${db_admin_password[0]:=$noDefine}
  # Valeurs par défault des variables du script
  _end=0      # sortie de menu
  _exit=0     # sortie de script
  _error=0    # gestion d'exception
  errorLog="${0%.sh}_temp.log"      # fichier de log temporaire
  archiveLog="${0%.sh}_arch.log"    # fichier de log permanent
  # Initialisation du fichier de log temporaire
  echo '' > ${errorLog}
  # Liste des fonctions autorisées en mode direct
  direct_function=("create_user" "delete_user" "alter_user_password" \
  "check_user" "test_user_exist" "create_db" "delete_db" "alter_db_owner" \
  "test_db_exist")
}

## GESTION DU MODE DIRECT ##

function direct_mode
{ # Exécute les commandes passées en argument au regard des options

  # Réinitialisation du fichier temporaire de log
  echo '' > ${errorLog}
  _error=0
  # Teste si les informations de connexion au SGDB sont définies
  if [ "${db_host[1]}" = "${noDefine}" ] ||
  [ "${db_admin_password[1]}" = "${noDefine}" ]
  then
    msg="\nL'hôte du SGDB et le mot passe du compte ${db_admin[1]} "
    msg+="doivent être définis !\n"
    echo -e "${msg}" >> ${errorLog}
    cat ${errorLog} ; cat ${errorLog} >> ${archiveLog}
    return 1
  fi
  # Exécute les commandes passées en arguments
  for cmd in $@ ; do
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
      eval "${cmd}" || cat ${errorLog}
    fi
    [ "${_error}" = 1 ] &&
    echo "Le méthode '${cmd}' est non autorisée en mode direct." &&
    return 1
  done
  return 0
}

## GESTION DU MODE INTERACTIF ##

function __menu_db_user
{ # Gère les opérations sur les comptes utilisateurs
  # Dépendances :
  #   - Fonctions: create_user, delete_user, alter_user_password
  #                manage_sql_error

  clear
  # Initialisation des variables d'état
  _end=0
  _exit=0
  _error=0
  echo '' > ${errorLog}

  # Définiion des options de menu
  local opt1="Définiion du compte (login : password) => "
  local opt1+="${db_user[1]} : ${db_user_password[1]},"
  local opt2="Créer le compte,"
  local opt3="Supprimer le compte"
  local opt4="Changer le mot de passe du compte,"
  local opt5="Réinitialiser ces valeurs,"
  local opt6="Retour au menu principal,"
  local opt7="Quitter."
  local menuPrincipal=("$opt1" "$opt2" "$opt3" "$opt4" "$opt5" "$opt6" "$opt7")

  # Mise en place du menu
  echo -e "\n##########"
  echo -e "#  GESTION DES UTILISATEURS"
  echo -e "#  script : ${0}"
  echo -e "#  compte administrateur : ${db_admin[1]} : ${db_admin_password[1]}"
  echo -e "#  serveur : ${db_host[1]}:${db_port[1]}"
  echo -e "#  dernière commande sql : ${sql}"
  echo -e "##########\n"
  select choix in "${menuPrincipal[@]}"
  do
    r=''
    case $choix in
      "$opt1" ) # Reccueil des données obligatoires
        v=${db_user[1]}
        echo -ne "Nom du compte (${v}) ? " ; read r
        db_user[1]=${r:=$v}
        r=''; w=${db_user_password[1]} ; v=${db_user[1]}
        echo -ne "Mot de passe du compte ${v} (${w}) ? " ; read r
        db_user_password[1]=${r:=$w}
        return 0 ;;
      "$opt2" ) # Création du compte
        check_user && return 0
        manage_sql_error
        return 1 ;;
      "$opt3" ) # Suppression du compte
        echo -ne "Confirmez la suppression du compte ${db_user[1]} ? (O/Y) : "
        read r
        if [[ $r = [OY] ]] ; then
          delete_user && return 0
        else
          echo -ne "Abandon de la commande de suppression."
          read ; return 0
        fi
        manage_sql_error
        return 1 ;;
      "$opt4" ) # Modification du mot de passe
        v=${db_user[1]} ; w=${db_user_password[1]}
        msg="Confirmez la modification du mot de passe ${w} du compte ${v} ?"
        msg+=" (O/Y) : "
        echo -ne "$msg"
        read r
        if [[ $r = [OY] ]] ; then
          alter_user_password && return 0
        else
          echo -ne "Abandon de la commande de modification."
          read ; return 0
        fi
        manage_sql_error
        return 1 ;;
      "$opt5" ) # Réinitialisation des variables
        db_user[1]=${db_user[0]:=$noDefine}
        db_user_password[1]=${db_user_password[0]:=$noDefine}
        return 0 ;;
      "$opt6" ) # Retour au menu principal
        _end=1
        return 0 ;;
      "$opt7" ) # Abandon du programme
        _end=1 ; _exit=1
        return  0 ;;
    esac
  done
}

function __menu_db
{ # Gère les opérations sur les bases de données
  # Dépendances :
  #   - Fonctions: create_db, delete_db, alter_db_owner, test_user_exist
  #                manage_sql_error

  clear

  # Initialisation des variables d'état
  _end=0
  _exit=0
  _error=0
  echo '' > ${errorLog}

  # Définiion des options de menu
  local opt1="Définiion de la base (nom : propriétaire) => "
  local opt1+="${db_name[1]} : ${db_user[1]},"
  local opt2="Créer la base de données,"
  local opt3="Supprimer la base de données,"
  local opt4="Changer le propriétaire,"
  local opt5="Réinitialiser ces valeurs,"
  local opt6="Retour au menu principal,"
  local opt7="Quitter."
  local menuPrincipal=("$opt1" "$opt2" "$opt3" "$opt4" "$opt5" "$opt6" "$opt7")

  # Mise en place du menu
  echo -e "\n##########"
  echo -e "#  GESTION DES BASES DE DONNÉES"
  echo -e "#  script : ${0}"
  echo -e "#  compte administrateur : ${db_admin[1]} : ${db_admin_password[1]}"
  echo -e "#  serveur : ${db_host[1]}:${db_port[1]}"
  echo -e "#  dernière commande sql : ${sql}"
  echo -e "##########\n"
  select choix in "${menuPrincipal[@]}"
  do
    r=''
    case $choix in
      "$opt1" ) # Reccueil des données obligatoires
        v=${db_name[1]}
        echo -ne "Nom de la base de données (${v}) ? " ; read r
        db_name[1]=${r:=$v}
        r='' ; w=${db_user[1]}
        echo -ne "Nom du compte propriétaire de la base (${w}) ? " ; read r
        db_user[1]=${r:=$w}
        r=''
        test_user_exist
        if [ $result_user = 0 ] ; then
          echo -ne "Le compte ${db_user[1]} n'existe pas !\n"
          echo -ne "Voulez-vous créer ce compte ? (O/Y) :" ; read r
          if [[ $r = [OY] ]] ; then
            echo -ne "Mot de passe du compte ${db_user[1]} ? " ; read r 
            db_user_password[1]=${r:=db_user_password[1]}
            # Si oui le créer
            create_user && return 0
            read ; return 1
          else
            echo -ne "Réinitialisation du compte propriétaire à '${db_user[0]}'"
            db_user[1]=${db_user[0]}
            read
          fi
        fi
        return 0 ;;
      "$opt2" ) # Création de la base de données
        check_db && return 0
        manage_sql_error
        return 1 ;;
      "$opt3" ) # Suppression de la base de données
        echo -ne "Confirmez la suppression de la base ${db_name[1]} ? (O/Y) : "
        read r
        if [[ $r = [OY] ]] ; then
          delete_db && return 0
        else
          echo -ne "Abandon de la commande de suppression."
          read ; return 1
        fi
        manage_sql_error
        return 1 ;;
      "$opt4" ) # Modification du propriétaire de la base de données
        v=${db_name[1]} ; w=${db_user[1]}
        msg="Confirmez le changement de propriétaire de la base ${v}"
        msg+=" pour le compte ${w} ? (O/Y) : "
        echo -ne "${msg}" ; read r
        if [[ $r = [OY] ]] ; then
          alter_db_owner && return 0
        else
          echo -ne "Abandon de la commande de modification."
          read ; return 1
        fi
        manage_sql_error
        return 1 ;;
      "$opt5" ) # Réinitialisation des variables
        db_name[1]=${db_name[0]:=$noDefine}
        db_user[1]=${db_user[0]:=$noDefine}
        return 0 ;;
      "$opt6" ) # Retour au menu principal
        _end=1
        return 0 ;;
      "$opt7" ) # Abandon du programme
        _end=1 ; _exit=1
        return  0 ;;
    esac
  done
}

function interactive_mode
{ # Gère les interactions utilisateur / script au travers de menus de sélection
  # Dépendances :
  #   - Fonctions: __menu_db_user, __menu_db, sql_apply

  clear

  # Définiion des options de menu
  local opt1="Adresse ou FQDN de l'hôte du SGDB  => ${db_host[1]},"
  local opt2="Port d'écoute du SGDB              => ${db_port[1]},"
  local opt3="Compte d'administration            => ${db_admin[1]},"
  local opt4="Mot de passe du compte ${db_admin[1]:=}"
  local opt4+="    => ${db_admin_password[1]},"
  local opt5="Gestion des comptes utilisateurs,"
  local opt6="Gestion des bases de données,"
  local opt7="Application d'un code SQL,"
  local opt8="Réinitialiser ces valeurs,"
  local opt9="Réinitialiser toutes les valeurs,"
  local opt10="Quitter."
  local menuPrincipal=("$opt1" "$opt2" "$opt3" "$opt4" "$opt5" "$opt6" "$opt7" \
  "$opt8" "$opt9" "$opt10")

  # Mise en place du menu
  echo -e "\n##########"
  echo -e "#  MENU PRINCIPAL DE GESTION"
  echo -e "#  script : ${0}"
  echo -e "#  dernière commande sql : ${sql}"
  echo -e "##########\n"
  select choix in "${menuPrincipal[@]}"
  do
    r=''
    case $choix in
      "$opt1" )
        v=${db_host[1]}
        echo -ne "IP ou FQDN du SGDB (${v}) ? " ; read r
        db_host[1]=${r:=$v}
        return 0 ;;
      "$opt2" )
        v=${db_port[1]}
        echo -ne "Port d'ecoute du SGDB (${v}) ? " ; read r
        db_port[1]=${r:=$v}
        return 0 ;;
      "$opt3" )
        v=${db_admin[1]}
        echo -ne "Compte d'administration (${v}) ? " ; read r
        db_admin[1]=${r:=$v}
        return 0 ;;
      "$opt4" )
        v=${db_admin_password[1]}
        echo -ne "Mot de passe du compte ${db_admin[1]} (${v}) ? "
        read r 
        db_admin_password[1]=${r:=$v}
        return 0 ;;
      "$opt5" ) # Sélection du menu de gestion des comptes
      if [ "${db_admin_password[1]}" = "${noDefine}" ]
        then
          msg="Le mot de passe ${db_admin_password[1]}"
          msg+=" du compte d'administration ${db_admin[1]} est incorrect !"
          echo "${msg}"
          read
          return 0
        fi
        while true ; do
          __menu_db_user
          [ $_end = 1 ] && break
        done
        _end=0
        return 0 ;;
      "$opt6" )
        if [ "${db_admin_password[1]}" = "${noDefine}" ]
        then
          msg="Le mot de passe ${db_admin_password[1]}"
          msg+=" du compte d'administration ${db_admin[1]} est incorrect !"
          echo "${msg}"
          read
          return 0
        fi
        while true ; do
          __menu_db
          [ $_end = 1 ] && break
        done
        _end=0
        return 0 ;;
      "$opt7" ) # Sélection du menu de gestion des bases
        if [ "${db_admin_password[1]}" = "${noDefine}" ]
        then
          msg="Le mot de passe ${db_admin_password[1]}"
          msg+=" du compte d'administration ${db_admin[1]} est incorrect !"
          echo "${msg}"
          read
          return 0
        fi
        msg="Veuillez saisir le code SQL à appliquer : "
        echo -e "${msg}" ; read r
        sql_apply "$r" && return 0 ;;
      "$opt8" ) # Réinitialisation des variables du menu
        db_host[1]=${db_host[0]:=$noDefine}
        db_port[1]=${db_port[0]:='5432'}
        db_name[1]=${db_name[0]:=$noDefine}
        return 0 ;;
      "$opt9" ) # Réinitialisation globale des variables
        __init_var || return 1
        return 0 ;;
      "$opt10" )
        _exit=1
        return 0 ;;
        * ) continue ;;
    esac
  done
}

function execution_mode
{ # Détermine le mode d'exécution du script : intéractif | direct
  # Dépendances :
  #   - Fonctions: __init_var, interactive_mode, direct_mode

  # Initialisation des variables de travail globales
  __init_var
  local _interMode=0
  local _directMode=0
  local _help=0

  # Traitement des options de la ligne de commande
  # Stockage dans les variables initiales globales
  OPTIND=0
  while getopts ":h:p:d:u:w:U:W:iH-:" opt ; do
    case $opt in
      h) db_host[0]=$OPTARG ;;
      p) db_port[0]=$OPTARG ;;
      d) db_name[0]=$OPTARG ;;
      u) db_user[0]=$OPTARG ;;
      w) db_user_password[0]=$OPTARG ;;
      U) db_admin[0]=$OPTARGS ;;
      W) db_admin_password[0]=$OPTARG ;;
      i) _interMode=1 ; echo 'Mode interactif' ;;
      H) _help=1 ;;
    esac
  done
  shift $((OPTIND-1))

  # Mise à jour des variables globales de travail
  __init_var || return 1

  # Sélection du mode
  # Demande d'exécution intéractive ?
  if [ $_interMode = 1 ] ; then
    while true ; do
      interactive_mode $@
      [ $? -ne 0 ] && return 1
      [ $_exit = 1 ] && break
    done
  else
    _directMode=1
  fi
  # Demande d'exécution directe ?
  if [ $_directMode = 1 ] ; then
    direct_mode $@
    [ $_error = 0 ] && return 0 || return 1      
  fi
  [ $? = 0 ] && return 0 || return 1
}

execution_mode $@
