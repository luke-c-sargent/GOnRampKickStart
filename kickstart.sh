#!/usr/bin/env bash
RED=$(tput setaf 1)
NC=$(tput sgr0)

SECONDS=0

PFX="[G-OnRamp]"


TRANSPORT_CFG_LINE="transport = paramiko"

WORKFLOWS=https://github.com/goeckslab/G-OnRamp-workflows
EXTRACT_DIR=G-OnRamp-workflows-master

GKS_SHA_PIN=31b9ff9390d7d199fc968241027f96f8493cd8b2 #e7dd64b6bc35400fa41e2dec18a68c55d0beb128
SHALLOW_SINCE=2019-02-01

SHALLOW="--shallow-since=$SHALLOW_SINCE"

# bash check
if [ ! "$BASH_VERSION" ] ; then
  printf "${RED}ERROR${NC}: This script (%s) requires bash; please execute it directly:\n\t./%s <options>\n" "$0" "$0" 1>&2
  exit 1
fi

usage () {
  printf "
Usage:
  %s <optional arguments and flags>

Optional Arguments:
  -t \"comma,seperated,tags\"
\t- tags to run, to the exclusion of all other tags
\t\t\tOR
  -s \"comma,seperated,tags\"
\t- tags to skip, running all other tags
\t\tNOTE: the -t and -s options are mutually exclusive
  -v N
\t- verbosity of output, where N is an integer (1 2 3 or 4)
Optional Flags:
  -i
\tinstall gonrampkickstart only -- stops before running ansible\n
EXPERIMENTAL FLAG, NOT READY FOR USE:
  -l
\tinstall locally without ssh - IN DEVELOPMENT USE AT YOUR OWN RISK\n" "$0"
}

TAGSTRING=""
INSTALL=1
LOCAL=1

while (( "$#" )); do
  case $1 in
    -i | --install_only )
      INSTALL=0
      shift 1
      ;;
    -l | --local )
      LOCAL=0
      shift 1
      ;;
    -h | --help )
      usage
      exit 0
      ;;
    -t | --tags )
      TAGSTRING="--tags $2 "
      shift 2
      ;;
    -s | --skip-tags )
      TAGSTRING="--skip-tags $2 "
      shift 2
      ;;
    -v | --version )
      if ! [[ "$2" =~ ^[0-9]+$ ]]
      then
        echo "ERROR: -v is not an integer"
        exit 1
      elif [ "$2" -ge 1 ] && [ "$2" -le 4 ]
      then
        vs=`printf '%*s' "$2" | tr ' ' "v"`
        TAGSTRING="-$vs "
        shift 2
      else
        echo "ERROR: -v value $2 is not in range [1..4]"
        exit 1
      fi
      ;;
    "" )
    ;;
    * )
      usage
      exit 1
  esac
done

# ensure correct version of ansible
ANSIBLE_REQUIRED_MAJOR="2"
ANSIBLE_REQUIRED_MINOR="7"

ANSIBLE_VERSION=$(ansible --version | head -n 1 | cut -d " " -f 2)
MAJOR="$(echo $ANSIBLE_VERSION | cut -d '.' -f 1)"
MINOR="$(echo $ANSIBLE_VERSION | cut -d '.' -f 2)"

if (( "$MAJOR" < "$ANSIBLE_REQUIRED_MAJOR" || "$MAJOR" == "$ANSIBLE_REQUIRED_MAJOR" && "$MINOR" < "$ANSIBLE_REQUIRED_MINOR" )) ; then
  printf "
[${RED}ERROR${NC}]: insufficient ansible version (found $ANSIBLE_VERSION, require $ANSIBLE_REQUIRED_MAJOR.$ANSIBLE_REQUIRED_MINOR or later )\n"
  printf "...please install latest ansible by:
  1. ensuring you have software-properties-common:
\t$ sudo apt install software-properties-common
  2. adding the ansible repository:
\t$ sudo apt-add-repository --yes --update ppa:ansible/ansible
  3. download package information from all sources:
\t$ sudo apt update
  4. upgrade or install ansible:
\t$ sudo apt upgrade ansible
  5. check for success:
\t$ ansible --version

"
  exit
fi

echo "$PFX ansible $ANSIBLE_VERSION found, acquiring GalaxyKickStart.."

if [ ! -d "./roles/galaxy.movedata" ]; then

  # acquire GKS
    # this requires a somewhat newer version of git (2.11+)
  git clone $SHALLOW https://github.com/ARTbio/GalaxyKickStart.git temporino
  cd temporino || exit
  git reset --hard $GKS_SHA_PIN


  # append line to ansible.cfg to force paramiko if sshpass absent
  if sshpass -V 1>/dev/null 2>&1
  then
    TRANSPORT_CFG_LINE="transport = ssh"
  else
    printf "${RED}WARNING!${NC} Paramiko transport selected. If there are errors / port conflicts while running script (particularly when resetting proftpd in the galaxy.movedata role), consider installing sshpass so that ansible can use ssh transport.\n"
  fi
  echo $TRANSPORT_CFG_LINE >> ansible.cfg
  cd .. || exit
  rm -f temporino/galaxy.yml
  rm -rf temporino/.git

  # acquire workflows
  mkdir -p gonramp/workflows
  git clone $WORKFLOWS --depth 1 roles/gonramp/workflows
  rm -rf roles/gonramp/workflows/LICENSE

  mv requirements_roles.yml ./temporino/requirements_roles.yml

  cp -a ./temporino/. .
  rm -rf temporino

  mv gonramp_vars group_vars/gonramp

  ansible-galaxy install -r requirements_roles.yml -p roles

else
  echo "$PFX previous GalaxyKickStart installation found, resuming"
fi

export ANSIBLE_HOST_KEY_CHECKING=False


if [[ $INSTALL -eq 0 ]]
then
  echo "gonrampkickstart initialized ... run:"
  echo "   $ ansible-playbook -i gonramp_inventory gonramp.yml"
  echo " ... to install g-onramp"
  exit
fi

# install galaxy, g-onramp tools and workflows, apollo
echo "$PFX Installing G-OnRamp ... "
printf "${RED}WARNING${NC}: This will take some time (multiple hours)\n"
if [[ $LOCAL -eq 0 ]]
then
  printf "${RED}WARNING${NC}: You have selected local installation -- this is experimental\n"
  ansible-playbook -i ./gonramp_local_inventory gonramp.yml $TAGSTRING --connection=local
else
  ansible-playbook -i ./gonramp_inventory gonramp.yml $TAGSTRING
fi
R=$?

if [[ $R -eq 0 ]]
then
  echo "$PFX G-OnRamp installation successful!"
else
  echo "G-OnRamp Installation failure"
fi

if (( $SECONDS > 3600 )) ; then
  let "hours=SECONDS/3600"
  let "minutes=(SECONDS%3600)/60"
  let "seconds=(SECONDS%3600)%60"
  echo "Completed in $hours hour(s), $minutes minute(s) and $seconds second(s)"
elif (( $SECONDS > 60 )) ; then
  let "minutes=(SECONDS%3600)/60"
  let "seconds=(SECONDS%3600)%60"
  echo "Completed in $minutes minute(s) and $seconds second(s)"
else
  echo "Completed in $SECONDS seconds"
fi
