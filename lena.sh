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

