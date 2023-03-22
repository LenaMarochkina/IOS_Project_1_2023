POSIXLY_CORRECT=yes

DIRECTORY=$('pwd')
FILE=""
COMMAND="open"
DATE_AFTER=""
DATE_BEFORE=""
MOST_USED=0
groups=()
MOLE_RC="./mole_json.json"

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

#Date validation
validate_date() {
  data=$(echo "$1" | awk '{
        if (split($1, a, "-") == 3) {
          year=a[1]
          month=a[2]
          day=a[3]
        }
        if (day < 1 || day > 31) {
          printf "Invalid date: %s", $0 >> "/dev/stderr"
        } else if (month < 1 || month > 12) {
          printf "Invalid date: %s", $0 >> "/dev/stderr"
        } else if (year < 0) {
          printf "Invalid date: %s", $0 >> "/dev/stderr"
        } else if (day == 31 && (month == 4 || month == 6 || month == 9 || month == 11)) {
          printf "Invalid date: %s", $0 >> "/dev/stderr"
        } else if (day >= 30 && month == 2) {
          printf "Invalid date: %s", $0 >> "/dev/stderr"
        } else if (day == 29 && month == 2 && (year % 4 != 0 || (year % 100 == 0 && year % 400 != 0))) {
          printf "Invalid date: %s", $0 >> "/dev/stderr"
        } else {
          print $0
        }
    }')
  echo "$data"
}

# parse arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
  -h | --help)
    print_help
    exit 0
    ;;
  -a)
    #    validate the date
    date=$(validate_date "$2")
    if [ "$date" = "$2" ]; then
      DATE_AFTER="$2"
    else
      echo "$date"
      exit 1
    fi

    shift 2
    ;;
  -b)
    #    validate the date
    date=$(validate_date "$2")
    if [ "$date" = "$2" ]; then
      DATE_BEFORE="$2"
    else
      echo "$date"
      exit 1
    fi

    shift 2
    ;;
  -g)
    IFS=',' read -r -a groups <<<"$2"
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

    # if argument is a file
    elif [ -f "$1" ]; then
      FILE="$1"
      shift

    # if argument is a directory
    elif [ -d "$1" ]; then
      DIRECTORY="$1"
      shift

    else
      FILE="$1"
    fi
    ;;
  esac
done

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

  #   config_path=$MOLE_RC

  config_path="./mole_json.json"

  if [ ! -f $config_path ]; then
    echo "$INITIAL_FILE_DATA" >$config_path
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
# @returns: filtered JSON data
filter_data() {
  #  json_groups="$(bash_array_to_json "$1")"
  data=$(echo "$CONFIG_DATA" | jq ".history")
  # Filter by GROUPS
  if [ -n "$groups" ]; then
    # get group array into string for correct jq parsing
    groups_str="$(printf "\"%s\"," "${groups[@]}" | sed 's/,$//')"
    data=$(echo "$data" | jq "map(if (.group - (.group - [$groups_str])) | length | . > 0  then . else empty end)")
  fi
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
  echo "$data"
}

# Check if file is in history, if not, add it
# @param $1: file path
# @returns: 0 if file is not in history, 1 if it is
check_if_file_in_history() {
  # checks if file is already in history, if not, adds it
  file_path=$(readlink -f "$1")
  if [ -z "$(echo "$CONFIG_DATA" | jq ".history[] | select(.path==\"$file_path\")")" ]; then
    echo false
  else
    echo true
  fi
}

# Adds file to history if it doesn't exist and updates it
# @param $1: file name
process_file() {
  file_in_history="$(check_if_file_in_history "$1")"
  if [ "$file_in_history" == "false" ]; then
    echo "file not zero"
    name=$(basename "$1")
    CONFIG_DATA=$(echo "$CONFIG_DATA" | jq ".history += [{\"name\": \"$name\", \"path\": \"$1\", \"group\": [], \"dates\": []}]")
  fi
  update_file_history "$1"
}

# Updates file history with groups and time
# @param $1: file path
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
  history_temp=$(echo "$CONFIG_DATA" | jq ".history | map(if(.path == \"$1\") then if any(.group[]; . == \"$2\") then . else .group+=[\"$2\"] end else . end)")
  CONFIG_DATA=$(echo "$CONFIG_DATA" | jq "select(.).history = $history_temp")
}

# Adds date to file
# @param $1: file name
add_file_time() {
  history_temp=$(echo "$CONFIG_DATA" | jq ".history | map(if(.path == \"$1\") then .dates = [\"$(date +"%Y-%m-%d_%H-%M-%S")\"] + .dates else . end)")
  CONFIG_DATA=$(echo "$CONFIG_DATA" | jq "select(.).history = $history_temp")
}

output_data_to_json() {
  echo "$1" | jq '.' > "$MOLE_RC"
}

# Get most frequently used file
# @param $1: file name
most_frequently_used() {
  #  if [ -z "$1" ]; then
  #    echo "No first arg"
  #  fi
  #
  #  data=$(echo "$CONFIG_DATA" | jq ".history[0].dates")
  #  echo "$data" | jq ". | length"
  echo ""
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

# Choose file to open
choose_file() {
  if [[ "$MOST_USED" == 1 ]]; then
    data=$(echo "$PREPROCESSED_DATA" | jq "sort_by(.popularity) | reverse")
    FILE=$(echo "$data" | jq ".[0].name" | tr -d '"')
  else
    data=$(echo "$PREPROCESSED_DATA" | jq "sort_by(.dates) | reverse")
    FILE=$(echo "$data" | jq ".[0].name" | tr -d '"')
  fi
  echo "$FILE"
}

# Open command handler
process_open() {
  if [[ -z "$FILE" ]]; then
    FILE=$(choose_file)
  fi
  file_path=$(readlink -f "$FILE")
  process_file "$file_path"
  FILE_EDITOR=$(get_file_editor)
  #  eval "$FILE_EDITOR" "$FILE"
  exit_code=$?
  output_data_to_json "$CONFIG_DATA"
  echo "$exit_code"
  return "$exit_code"
}

# List command handler
process_list() {
  # TODO: add tabulation and remove the last iteration + '-' for files without groups
  FILTERED_HISTORY=$(echo "$FILTERED_HISTORY" | jq " sort_by(.name) | sort_by(.group)")
  max_indent=$(echo "$FILTERED_HISTORY" | jq "max_by(.name | length) | .name | length")
  range=$(echo "$FILTERED_HISTORY" | jq ". | length ")
  range=$((range - 1))
  for i in $(seq 0 "$range"); do
    name_length=$(echo "$FILTERED_HISTORY" | jq ".[$i].name | length")
    spaces_number=$(($max_indent - $name_length))
    indent=$(create_indent "$spaces_number")
    line=$(echo "$FILTERED_HISTORY" | jq "\"\(.[$i].name):$indent \(if .[$i].group | length | . > 0 then (.[$i].group | join(\",\"))  else \"-\" end)\"" | tr -d '"')
    echo "$line"
  done
}

# Get secret log path
# @returns: path to secret log
get_secret_log_path() {
  secret_log_path=$(dirname "$MOLE_RC")
  user_name="$(whoami)"
  date="$(date +"%Y-%m-%d_%H-%M-%S")"
  secret_log_path+="/log_"$user_name"_"$date".bz2"
  echo "$secret_log_path"
}

process_secret_log() {
  FILTERED_HISTORY=$(echo "$FILTERED_HISTORY" | jq " sort_by(.path)")
  range=$(echo "$FILTERED_HISTORY" | jq ". | length ")
  range=$((range - 1))
  for i in $(seq 0 "$range"); do
    line=$(echo "$FILTERED_HISTORY" | jq "\"\(.[$i].path);\(.[$i].dates | reverse | join(\";\"))\"" | tr -d '"')
    echo "$line" | bzip2 >>"$(get_secret_log_path)"
  done
}

# create indentation
# @param $1: number of spaces
# @returns: indentation string
create_indent() {
  ident=""
  for i in $(seq 1 "$1"); do
    ident+=" "
  done
  echo "$ident"
}

#most_frequently_used abc
#CONFIG_DATA=$(filter_data)
#array=("bash" "git")
#bash_array_to_json "${array[@]}"
#check_if_file_in_history .cockrc
#process_file .cock

#echo "$CONFIG_DATA"
#preprocess_data
#echo "$PREPROCESSED_DATA"

#add_file_group .gitconfig git2
#add_file_time .gitconfig
#process_open
#echo "$CONFIG_DATA"
#execute_command "$COMMAND"
#process_open
process_secret_log
#echo "$FILE"
#process_list
#bash_array_to_json "${groups[@]}"

