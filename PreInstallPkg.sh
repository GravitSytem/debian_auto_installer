# PreInstallPkg.sh

function make_env() {
    db_file="./gdirectory.lst"
    nb_line=`cat $db_file | wc -l`
    h=0
    while [ $h -lt $nb_line ]; do
        h=$((h+1))
        search=`head -${h} $db_file | tail -1`
        ptr=$search
        mkdir ptr
        if [ $search = $nb_line ]; then
            db_file="./gfile.lst"
            h=0
        fi
    done
}

function check_root() {
    if [ ! $EUID = 0 ]; then 
        echo "2" >> $cmd_descriptor
        echo "[ ! ] : No root system detected ! ... Quit Programm " >> $log
        exit 0
    fi
}

function PreInstall(){
    apt update
    apt install -y debootstrap
}

check_root
make_env
PreInstall
