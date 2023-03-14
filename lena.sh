## parse arguments
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

echo "File: $FILE"
echo "Directory: $DIRECTORY"
echo "Command: $COMMAND"
echo "Date_after: $DATE_AFTER"
echo "Date_before: $DATE_BEFORE"
echo "Most_used: $MOST_USED"
