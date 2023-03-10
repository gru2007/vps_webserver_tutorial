#!/bin/bash

export SYSTEMD_PAGER=''
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

function SetLogFile {
    export LOG_FILE="/tmp/install_fastpanel.debug"

    if [ -f "$LOG_FILE" ]; then
        rm "$LOG_FILE"
    fi
    
    exec 3>&1
    exec &> $LOG_FILE
}

function ParseParameters {
    CheckArch    
    CheckVersionOS
    while [ "$1" != "" ]; do
        case $1 in
            -m | --mysql )          shift
                                    ChooseMySQLVersion $1
                                    ;;
            -f | --force )          export force=1
                                    ;;
            -o | --only-panel )     export minimal=1
                                    ;;
            -h | --help )           Usage
                                    exit
                                    ;;
            * )                     Usage
                                    Error "Неизвестная опция: \"$1\"."
        esac
        shift
    done
}

function ChooseMySQLVersion {
    shopt -s extglob
    local versions="@(${AVAILABLE_MYSQL_VERSIONS})"
    case "$1" in
        $versions )              export MYSQL_VERSION=$1
                                ;;
        * )                     Usage
                                Error "Неизвестная версия MySQL: \"$1\"."
                                ;;
    esac
}

function Usage {
    cat << EOU >&3

Использование:  $0 [-h|--help]
                $0 [-f|--force] [-m|--mysql <mysql_version>]

Опции:
    -h, --help             Отобразить эту помощь
    -f, --force            Пропустить проверку установленного ПО (nginx, MySQL, apache2)
    -m, --mysql            Установить версию MySQL для установки
            Доступные версии: ${AVAILABLE_MYSQL_VERSIONS}
EOU
}

function Greeting {
    ShowLogo
    Message "Поздравляем пользователь!\n\nСейчас будет установлена лучшая панель для тебя!\n\n"
}

function CheckPreinstalledPackages {
    case `dpkg --get-selections |grep -E "fastpanel2\s+install" -c` in
        0 )     Debug "Пакет 'fastpanel2' не установлен."
                ;;
        1 )     Error "Пакет FASTPANEL уже установлен. Выход.\n"
                ;;
    esac

    local PACKAGES="nginx apache2 "
    for package in ${PACKAGES}; do
        case `dpkg --get-selections |grep -E "${package}\s+install" -c` in
            0 )     Debug "Пакет '${package}' не установлен."
                    ;;
            * )     INSTALLED_SOFTWARE+=("${package}")
                    ;;
        esac
    done
    
    for package in mysql-server mariadb-server percona-server-server percona-server-server-5.6 percona-server-server-5.7; do
        case `dpkg --get-selections |grep -E "${package}\s+install" -c` in
            0 )     Debug "Пакет '${package}' не установлен."
                    ;;
            * )     Error "\nПанель управления может быть установлена только на чистую ОС.\nК сожалению установка с уже установенным MYSQL невозможна."
                    ;;
        esac
    done
}


function InstallationFailed {
    if [ ! -z "$1" ]; then
        Debug "$1"
    fi
    printf "\033[1;31m[Неудачно]\033[0m\n" >&3
    printf "\033[1;31m\nУппс! Я не смог установить панель... Пожалуйста посмотрите причину в лог файле - \"${LOG_FILE}\".'\nВы так же можете отправить лог создателям FASTPANEL https://cp.fastpanel.direct/ и они постараются вам помочь!\033[0m\n" >&3
    exit 1
}

function Error {
    printf "\033[1;31m$@\033[0m\n" >&3
    exit 1
}

function Message {
    printf "\033[1;36m$@\033[0m" >&3
    Debug "$@\n"
}

function Warning {
    printf "\033[1;35m$@\033[0m" >&3
    Debug "$@\n"
}

function Info {
    printf "\033[00;32m$@\033[0m" >&3
    Debug "$@\n"
}

function Debug {
    printf "$@\n"
}

function Success {
    printf "\033[00;32m[Success]\n\033[0m" >&3
}

function generatePassword {
    LENGHT="16"
    if [ ! -z "$1" ]; then
        LENGHT="$1"
    fi
    openssl rand -base64 64 | tr -dc a-zA-Z0-9=+ | fold -w ${LENGHT} |head -1
}

function UpdateSoftwareList {
    apt-get update -qq || InstallationFailed "Пожалуйста проверьте apt"
}

function InstallMySQLService {
    UpdateSoftwareList
    case ${MYSQL_VERSION} in
        mysql5.6 )              source /usr/share/fastpanel2/bin/mysql/install-mysql5.6.sh
                                ;;
        mysql5.7 )              source /usr/share/fastpanel2/bin/mysql/install-mysql5.7.sh
                                ;;
        mysql8.0 )              source /usr/share/fastpanel2/bin/mysql/install-mysql8.0.sh
                                ;;
        mariadb10.2 )           source /usr/share/fastpanel2/bin/mysql/install-mariadb10.2.sh
                                ;;
        mariadb10.3 )           source /usr/share/fastpanel2/bin/mysql/install-mariadb10.3.sh
                                ;;
        mariadb10.4 )           source /usr/share/fastpanel2/bin/mysql/install-mariadb10.4.sh
                                ;;
        mariadb10.5 )           source /usr/share/fastpanel2/bin/mysql/install-mariadb10.5.sh
                                ;;
        mariadb10.6 )           source /usr/share/fastpanel2/bin/mysql/install-mariadb10.6.sh
                                ;;
        percona5.6 )            source /usr/share/fastpanel2/bin/mysql/install-percona5.6.sh
                                ;;
        percona5.7 )            source /usr/share/fastpanel2/bin/mysql/install-percona5.7.sh
                                ;;
        percona8.0 )            source /usr/share/fastpanel2/bin/mysql/install-percona8.0.sh
                                ;;
        default )               source /usr/share/fastpanel2/bin/mysql/install-default.sh
                                ;;
        * )                     Debug "Сбой импорта функции MySQL" && InstallationFailed
                                ;;
    esac
    installMySQL || InstallationFailed
    Success
}

function InstallPanelRepository {
    Debug "Настройка репозитория FASTPANEL.\n"

    Debug "Добавление ключа с http://repo.fastpanel.direct/."
    wget -q http://repo.fastpanel.direct/RPM-GPG-KEY-fastpanel -O - | apt-key add -  || InstallationFailed

    Debug "Добавление файла /etc/apt/sources.list.d/fastpanel2.list"
    echo "deb [arch=amd64] http://repo.fastpanel.direct ${OS} main" > /etc/apt/sources.list.d/fastpanel2.list
}

function CheckVersionOS {
    source /etc/os-release
    case ${ID} in
        debian )    export FAMILY='debian'
                    case ${VERSION_ID} in
                        8 )             export OS='jessie'
                                        export AVAILABLE_MYSQL_VERSIONS='default|mariadb10.2|mariadb10.3|mariadb10.4|percona5.6|percona5.7'
                                        export MYSQL_VERSION='default'
                                        ;;
                        9 )             export OS='stretch'
                                        export AVAILABLE_MYSQL_VERSIONS='default|mariadb10.2|mariadb10.3|mariadb10.4|mariadb10.5|percona5.6|percona5.7|percona8.0'
                                        export MYSQL_VERSION='percona5.7'
                                        ;;
                        10 )            export OS='buster'
                                        export AVAILABLE_MYSQL_VERSIONS='default|mariadb10.2|mariadb10.3|mariadb10.4|mariadb10.5|mysql5.7|mysql8.0|percona5.7|percona8.0'
                                        export MYSQL_VERSION='mysql5.7'
                                        ;;
                        11 )            export OS='bullseye'
                                        export AVAILABLE_MYSQL_VERSIONS='default|mariadb10.5|mysql8.0|percona8.0'
                                        export MYSQL_VERSION='mysql8.0'
                                        ;;
                        * )             Error 'Неподдерживаемая версия Debian.'
                                        ;;
                    esac
                    ;;
        ubuntu )    export FAMILY='ubuntu'
                    case ${VERSION_ID} in
                        22.04 )         export OS='jammy'
                                        export AVAILABLE_MYSQL_VERSIONS='default'
                                        export MYSQL_VERSION='default'
                                        # fix for the old Ubuntu images
                                        echo 'libssl1.1 libraries/restart-without-asking boolean true' |  debconf-set-selections
                                        ;;
                        20.04 )         export OS='focal'
                                        export AVAILABLE_MYSQL_VERSIONS='default|mariadb10.3|mariadb10.4|mariadb10.5|mysql8.0|percona8.0'
                                        export MYSQL_VERSION='mysql8.0'
                                        # fix for the old Ubuntu images
                                        echo 'libssl1.1 libraries/restart-without-asking boolean true' |  debconf-set-selections
                                        ;;
                        18.04 )         export OS='bionic'
                                        export AVAILABLE_MYSQL_VERSIONS='default|mariadb10.2|mariadb10.3|mariadb10.4|mariadb10.5|mysql5.6|mysql5.7|mysql8.0|percona5.6|percona5.7|percona8.0'
                                        export MYSQL_VERSION='mysql5.7'
                                        # fix for the old Ubuntu images
                                        echo 'libssl1.1 libraries/restart-without-asking boolean true' |  debconf-set-selections
                                        ;;
                        * )             Error 'Неподдерживаемая версия Ubuntu.'
                                        ;;
                    esac
                    ;;
        * )         Error 'Неподдерживаемая OS.'
                    ;;
    esac
}

function CheckSystemd {
    Debug "Проверка службы инициализации.\n"
    case `dpkg --get-selections |grep -E "systemd-sysv\s+install" -c` in
        0 )     Error "OS ${OS} без systemd не поддерживается.\nПожалуйста установите пакет 'systemd-sysv'."
                ;;
        1 )     Debug "Пакет 'systemd-sysv' установлен."
                ;;
    esac
}

function CheckOpensshServer {
    Debug "Проверка что sshd установлен.\n"
    case `dpkg --get-selections |grep -E "openssh-server\s+install" -c` in
        0 )     Error "OS ${OS} без openssh-server не поддерживается.\nПожалуйста установите пакет 'openssh-server'."
                ;;
        1 )     Debug "Пакет 'openssh-server' установлен."
                ;;
    esac
}

function CheckArch {
    if [ `arch` = "x86_64" ]; then
        Debug "Архитектура x86_64."
    else
        Debug "FASTPANEL поддреживает только x86_64 архитектуру."
        InstallationFailed
    fi
}

function CheckGnupgPackage {
    case `dpkg --get-selections |grep -E "gnupg2?\s+install" -c` in
        0 )     Debug "Пакет 'gnupg' не установлен."
                UpdateSoftwareList
                apt-get install -y gnupg
                ;;
        * )     Debug "Пакет 'gnupg' установлен"
                ;;
    esac
}

function CheckServerConfiguration {
    export INSTALLED_SOFTWARE=''
    Message "Запуск проверки перед установкой\n"
    Message "OS:\t" && Info "${PRETTY_NAME}\n\n"
    CheckSystemd
    # CheckOpensshServer
    CheckPreinstalledPackages
    if [ "${INSTALLED_SOFTWARE[@]}" != '' ] && [ "${force}" != '1' ]; then
        Message "Было обнаружено, что установлено следующее программное обеспечение: ${INSTALLED_SOFTWARE}.\n"
        Warning "\nПанель управления может быть установлена только на чистую ОС.\nВы можете использовать флаг -f, чтобы игнорировать установленное программное обеспечение.\n"
        exit 1
    fi
    CheckGnupgPackage
}

function ShowLogo {
cat << "EOF" >&3
        _________   _______________  ___    _   __________ 
       / ____/   | / ___/_  __/ __ \/   |  / | / / ____/ / 
      / /_  / /| | \__ \ / / / /_/ / /| | /  |/ / __/ / /  
     / __/ / ___ |___/ // / / ____/ ___ |/ /|  / /___/ /___
    /_/   /_/  |_/____//_/ /_/   /_/  |_/_/ |_/_____/_____/ Ruslan's Translate

EOF
}

function Clean {
    apt-get clean
    # Closing file descriptor for debug log
    exec 3>&-
}

function InstallFastpanel {
    Message "Установка пакета FASTPANEL.\n"

    InstallPanelRepository
    UpdateSoftwareList

    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections

    apt-get install -qq -y fastpanel2 || InstallationFailed
    Success
}

function FinishInstallation {
    PASSWORD=`generatePassword 16` || InstallationFailed
    mogwai chpasswd -u fastuser -p $PASSWORD >/dev/null 2>&1
    export IP=`ip -o -4 address show scope global | tr '/' ' ' | awk '$3~/^inet/ && $2~/^(eth|veth|venet|ens|eno|enp)[0-9]+$|^enp[0-9]+s[0-9a-z]+$/ {print $4}'|head -1`
    echo ""
    Message "\nПоздравляем! FASTPANEL успешно установлена и доступна для вас на адресе https://$IP:8888/ .\n"
    Message "Логин: fastuser\n"
    Message "Пароль: $PASSWORD\n"
}

function InstallServices {
    if [ -z ${minimal} ]; then
        InstallMySQLService
        source /usr/share/fastpanel2/bin/install-web.sh
        InstallWebService
        source /usr/share/fastpanel2/bin/install-ftp.sh
        InstallFtpService
        source /usr/share/fastpanel2/bin/install-mail.sh
        InstallMailService
        source /usr/share/fastpanel2/bin/install-recommended.sh
        InstallRecommended
    else
        Debug "Выбрана минимальная установка."
    fi
}

function Run {
    SetLogFile
    ParseParameters $@
    Greeting
    CheckServerConfiguration
    InstallFastpanel
    InstallServices
    FinishInstallation
    Clean
}


Run $@

