POSIXLY_CORRECT=yes

DIRECTORY=$('pwd')
FILE=""
COMMAND="open"
DATE_AFTER=""
DATE_BEFORE=""
MOST_USED=0
groups=()

# parse arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
  -h | --help)
    print_help
    exit 0
    ;;
  -a)
    DATE_AFTER="$2"
    shift 2
    ;;
  -b)
    DATE_BEFORE="$2"
    shift 2
    ;;
  -g)
    IFS=',' read -r -a groups <<<"$2"
    echo "Groups: ${groups[*]}"
    shift 2
    ;;
  -m)
    MOST_USED=1
    shift
    ;;
  *)
    if [[ "$1" == "list" || "$1" == "secret-log" ]]; then
      COMMAND="$1"
      shift

    # TODO: if file/directory doesn't exist, leave it to the file editor to handle
    # if argument is a file
    elif [ -f "$1" ]; then
      FILE="$1"
      shift

    # if argument is a directory
    elif [ -d "$1" ]; then
      DIRECTORY="$1"
      shift
    fi
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

# Get file editor from the config file
get_file_editor() {
  EDITOR=$(echo "$CONFIG_DATA" | jq -r ".settings.EDITOR")
  VISUAL=$(echo "$CONFIG_DATA" | jq -r ".settings.VISUAL")

  if [ -z "$EDITOR" ]; then
    if [ -z "$VISUAL" ]; then
      FILE_EDITOR="vi"
    else
      FILE_EDITOR="$VISUAL"
    fi
  else
    FILE_EDITOR="$EDITOR"
  fi

  echo "$FILE_EDITOR"
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
  if [ -n "$DATE_AFTER" ]; then
    data=$(echo "$data" | jq "map(if(any(.dates[]; . > \"$DATE_AFTER\" )) then . else empty end)")
  fi
  # Filter by BEFORE_DATE
  if [ -n "$DATE_BEFORE" ]; then
    data=$(echo "$data" | jq "map(if(any(.dates[]; . < \"$DATE_BEFORE\")) then . else empty end)")
  fi
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

  update_file_history "$1"
}

# Updates file history with groups and time
# @param $1: file name
update_file_history() {
  for i in "${groups[@]}"; do
    add_file_group "$1" "$i"
  done

  add_file_time "$1"
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

# Executes command based on script argument
# @param $1: command name
execute_command() {
  if [[ "$1" == "open" ]]; then
    process_open
  elif [[ "$1" == "list" ]]; then
    process_list
  elif [[ "$1" == "secret-log" ]]; then
    process_secret_log
  fi
}

# Open command handler
process_open() {
  process_file "$FILE"

  FILE_EDITOR=$(get_file_editor)
  # remove from commentary in production
  #  eval "$FILE_EDITOR" "$FILE"
}

# List command handler
process_list() {
  # TODO: add tabulation and remove the last iteration
  range=$(echo "$FILTERED_HISTORY" | jq ". | length ")
  for i in $(seq 0 "$range"); do
    line=$(echo "$FILTERED_HISTORY" | jq "\"\(.["$i"].name): \(.[$i].group | join(\", \"))\"" | tr -d '"')
    echo "$line"
  done
}

process_secret_log() {
  echo ""
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
