#Arguments parsing
while getopts "hg:m:b:a:" opt; do
    case $opt in
        h)
            # Display help message
            print_help
            ;;
        g)
            # Handle the -g option
            IFS=',' read -r -a groups <<< "$OPTARG"
            echo "Groups: ${groups[*]}"
            ;;
        m)
            # Handle the -m option
            most_used=true
            ;;
        b)
            # Handle the -b option
            DATE_BEFORE=$OPTARG
            ;;
        a)
            # Handle the -a option
            DATE_AFTER=$OPTARG
            ;;
        \?)
            # Invalid option
            print_help
            ;;
    esac
done

#Date validation
validate_date() {
  data=$(echo "$1" | awk '{
        if (split($1, a, "-") == 3) {
          year=a[1]
          month=a[2]
          day=a[3]
        } else {
          printf "Invalid date: %s\n", $0 >> "/dev/stderr"
        }
        if (day < 1 || day > 31) {
          printf "Invalid date: %s\n", $0 >> "/dev/stderr"
        } else if (month < 1 || month > 12) {
          printf "Invalid date: %s\n", $0 >> "/dev/stderr"
        } else if (year < 0) {
          printf "Invalid date: %s\n", $0 >> "/dev/stderr"
        } else if (day == 31 && (month == 4 || month == 6 || month == 9 || month == 11)) {
          printf "Invalid date: %s\n", $0 >> "/dev/stderr"
        } else if (day >= 30 && month == 2) {
          printf "Invalid date: %s\n", $0 >> "/dev/stderr"
        } else if (day == 29 && month == 2 && (year % 4 != 0 || (year % 100 == 0 && year % 400 != 0))) {
          printf "Invalid date: %s\n", $0 >> "/dev/stderr"
        } else {
          print $0
        }
    }')
  echo "$data"
}

# Function print_help to output help message
print_help() {
  echo "  mole – wrapper pro efektivní použití textového editoru s možností automatického výběru nejčastěji či posledně modifikovaného souboru."
  echo "POUŽITÍ"
  echo "  mole -h"
  echo "  mole [-g GROUP] FILE"
  echo "  mole [-m] [FILTERS] [DIRECTORY]"
  echo "  mole list [FILTERS] [DIRECTORY]"
  echo "Popis"
  echo "  -h                                Vypíše nápovědu k použití skriptu"
  echo "  mole [-g GROUP] FILE              Zadaný soubor bude otevřen."
  echo "                                    Pokud byl zadán přepínač -g, dané otevření souboru bude zároveň přiřazeno"
  echo "                                    do skupiny s názvem GROUP. GROUP může být název jak existující, tak nové skupiny."
  echo "  mole [-m] [FILTERS] [DIRECTORY]   Pokud DIRECTORY odpovídá existujícímu adresáři, skript z daného adresáře vybere soubor, který má být otevřen."
  echo "  mole list [FILTERS] [DIRECTORY]   Skript zobrazí seznam souborů, které byly v daném adresáři otevřeny (editovány) pomocí skriptu."
  echo "Filtry"
  echo "  [-g GROUP1[,GROUP2[,...]]]        Specifikace skupin. Soubor bude uvažován (pro potřeby otevření nebo výpisu) pouze tehdy,"
  echo "                                    pokud jeho spuštění spadá alespoň do jedné z těchto skupin."
  echo "  [-a DATE]                         Záznamy o otevřených (editovaných) souborech před tímto datem nebudou uvažovány."
  echo "  [-b DATE]                         Záznamy o otevřených (editovaných) souborech po tomto datu nebudou uvažovány."
}

# Read config from JSON
# @param $1: path to JSON file
# @example: read_from_config file.json
# @returns: String with JSON config
read_from_config() {
  cat "$1" | jq -r "$2"
}

# Parse config file or create if not exists
# @example: parse_config_file
# @returns: String with JSON config
parse_config_file() {
  INITIAL_FILE_DATA="
    {
      \"settings\": {
        \"EDITOR\": \"nano\",
        \"VISUAL\": \"vi\"
      }
    }
  "

  # config_path=$MOLE_RC
  config_path="./mole_json.json"

  if [ ! -f $config_path ]; then
    echo "$INITIAL_FILE_DATA" > $config_path
  fi

  # TODO: Check is path exists and create with folders if needed

  read_from_config $config_path
}

# Data from config file
CONFIG_DATA=$(parse_config_file)

# Convert bash array to JSON array
# @param $1: array of groups
# @returns: JSON array
bash_array_to_json() {
  array="[]"

  for i in "$@"; do
    array=$(echo "$array" | jq ". += [\"$i\"]")
  done

  echo "$array"
}

# Filter JSON history data
# @param $1: array of groups
# @param $2: after date
# @param $3 before date
# @returns: filtered JSON data
filter_data() {
#  json_groups="$(bash_array_to_json "$1")"
  data=$(echo "$CONFIG_DATA" | jq ".history")
  # Filter by GROUPS
  data=$(echo "$data" | jq "map(if((.group - (.group - [\"bash\", \"git\"]) | length | . > 0)) then . else empty end)")
  # Filter by AFTER_DATE
  data=$(echo "$data" | jq "map(if(any(.dates[]; . > \"2020-01-01\")) then . else empty end)")
  # Filter by BEFORE_DATE
  data=$(echo "$data" | jq "map(if(any(.dates[]; . < \"2020-01-03\")) then . else empty end)")

  echo "$data"
}

# Filtered history
FILTERED_HISTORY=$(filter_data)

# Preprocess data
#   Adds popularity field
# @returns: preprocessed JSON data
preprocess_data() {
  data=$(echo "$FILTERED_HISTORY" | jq "map(. + {\"popularity\": (.dates | length)})")

  echo "$data"
}

PREPROCESSED_DATA=$(preprocess_data)

# Prepares data before saving
#   Removes popularity field
# @returns: data prepared for save
prepare_data_before_save() {
  data=$(echo "$1" | jq "del(.popularity)")
}

# Check if file is in history, if not, add it
# @param $1: file name
# @returns: 0 if file is not in history, 1 if it is
check_if_file_in_history() {
  # checks if file is already in history, if not, adds it
  if [ -z "$(echo "$CONFIG_DATA" | jq ".history[] | select(.name==\"$1\")")" ]; then
    return 0
  else
    return 1
  fi
}

# Adds file to history if it doesn't exist
# @param $1: file name
process_file() {
  file_in_history="$(check_if_file_in_history "$1")"

  if [ -z "$file_in_history" ]; then
    CONFIG_DATA=$(echo "$CONFIG_DATA" | jq ".history += [{\"name\": \"$1\", \"group\": [], \"dates\": []}]")
  fi

  update_file_history "$1" "$2"
}

# Adds group to file
# @param $1: file name
# @param $2: group name
add_file_group() {
  history_temp=$(echo "$CONFIG_DATA" | jq ".history | map(if(.name == \"$1\") then .group += [\"$2\"] else . end)")
  CONFIG_DATA=$(echo "$CONFIG_DATA" | jq "select(.).history = $history_temp")
}

# Adds date to file
# @param $1: file name
add_file_time() {
  history_temp=$(echo "$CONFIG_DATA" | jq ".history | map(if(.name == \"$1\") then .dates += [\"$(date +"%Y-%m-%d %T")\"] else . end)")
  CONFIG_DATA=$(echo "$CONFIG_DATA" | jq "select(.).history = $history_temp")
}

# Get most frequently used file
# @param $1: file name
most_frequently_used() {
  if [ -z "$1" ]; then
    echo "No first arg"
  fi

  data=$(echo "$CONFIG_DATA" | jq ".history[0].dates")
  echo "$data" | jq ". | length"
}

#most_frequently_used abc
#CONFIG_DATA=$(filter_data)
#array=("bash" "git")
#bash_array_to_json "${array[@]}"
#check_if_file_in_history .cockrc
#process_file .cock

#echo "$CONFIG_DATA"
#echo "$PREPROCESSED_DATA"

#add_file_group .gitconfig git2
#add_file_time .gitconfig
#process_open
#echo "$CONFIG_DATA"
#execute_command "$COMMAND"

echo "$FILTERED_HISTORY"

process_list
#bash_array_to_json "${groups[@]}"
