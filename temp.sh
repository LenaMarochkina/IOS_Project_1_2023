#data=$(cat "mole_json.json" | jq -r "$1")

# echo settings key
#echo "$data" | jq ".settings"

#read_from_config() {
#  cat "$1" | jq -r "$2"
#}
#
#read_from_config mole_json.json

read_from_config() {
  cat "$1" | jq -r "$2"
}

parse_config_file() {
  INITIAL_FILE_DATA="
    {
      \"settings\": {
        \"EDITOR\": \"nano\",
        \"VIRTUAL\": \"vi\"
      }
    }
  "

#  config_path=$MOLE_RC
  config_path="mole_create_test.json"

  if [ ! -f $config_path ]; then
    echo "$INITIAL_FILE_DATA" > $config_path
  fi

  read_from_config $config_path
}

str=$(parse_config_file)

echo "$str" | jq ".settings.EDITOR"
