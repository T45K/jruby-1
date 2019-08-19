#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# jruby.bash - Start Script for the JRuby interpreter
#
# Environment Variable Prequisites
#
#   JRUBY_OPTS    (Optional) Default JRuby command line args
#   JRUBY_SHELL   Where/What is system shell
#
#   JAVA_HOME     Must point at your Java Development Kit installation.
#
# -----------------------------------------------------------------------------

# ----- Set some default conditions for how we'll eventually run --------------
cygwin=false
use_exec=true

# ----- Identify OS we are running under --------------------------------------
case "`uname`" in
  CYGWIN*) cygwin=true;;
  Darwin) darwin=true;;
  MINGW*) jruby.exe "$@"; exit $?;;
esac

# ----- Determine how to call expr (jruby/jruby#5091) -------------------------
# On Alpine linux, expr takes no -- arguments, and 'expr --' echoes '--'.
_expr_dashed=$(expr -- 2>/dev/null)
if [ "$_expr_dashed" != '--' ] ; then
  alias expr="expr --"
fi
unset _expr_dashed

# ----- Verify and Set Required Environment Variables -------------------------
if [ -z "$JAVA_VM" ]; then
  JAVA_VM=-client
fi

# Gather environment information as we go
environment_log="JRuby Environment\n================="
function add_log() {
    printf -v environment_log "$environment_log\n$1"
}

# get the absolute path of the executable
BASE_DIR=$(cd -P -- "$(dirname -- "$BASH_SOURCE")" >/dev/null && pwd -P)
SELF_PATH="$BASE_DIR/$(basename -- "$BASH_SOURCE")"

# resolve symlinks
while [ -h "$SELF_PATH" ]; do
    # 1) cd to directory of the symlink
    # 2) cd to the directory of where the symlink points
    # 3) get the physical pwd
    # 4) append the basename
    SYM="$(readlink "$SELF_PATH")"
    SELF_PATH="$(cd "$BASE_DIR" && cd $(dirname -- "$SYM") && pwd -P)/$(basename -- "$SYM")"
done

JRUBY_HOME="${SELF_PATH%/*/*}"

add_log "JRuby executable: $BASH_SOURCE"
add_log "JRUBY_HOME: $JRUBY_HOME"

# Determine where the java command is and ensure we have a good JAVA_HOME
if [ -z "$JAVACMD" ] ; then
  if [ -z "$JAVA_HOME" ] ; then
    JAVACMD='java'
    JAVA_HOME=$(dirname $(dirname `which java`))
  else
    if $cygwin; then
      JAVACMD="`cygpath -u "$JAVA_HOME"`/bin/java"
    else
      JAVACMD="$JAVA_HOME/bin/java"
    fi
  fi
else
  expanded_javacmd=`which $JAVACMD`
  if [[ -z "$JAVA_HOME" && -x $expanded_javacmd ]] ; then
    JAVA_HOME=$(dirname $(dirname $expanded_javacmd))
  fi
fi

add_log "JAVACMD: $JAVACMD"
add_log "JAVA_HOME: $JAVA_HOME"

# Detect Java 9+ by the presence of a jmods directory in JAVA_HOME
if [ -d $JAVA_HOME/jmods ]; then
  is_java9=1
  add_log "Java modules detected"
fi


# We include options on the java command line in the following order:
# * JRuby installed bin/.jruby.java_opts (empty by default)
# * user directory .jruby.java_opts
# * current directory .jruby.java_opts
# * JAVA_OPTS environment variable
# * command line flags

if [ -z "$JRUBY_OPTS" ] ; then
  JRUBY_OPTS=""
fi

# On Java 9+, add an @argument for the given file if it exists.
# On earlier versions the file will be read and expanded
function process_java_opts {
  java_opts_file=$1
  if [[ -r $java_opts_file ]]; then
    add_log "Adding Java options from: $java_opts_file"
    if [[ $is_java9 ]]; then
      jruby_java_opts="$jruby_java_opts @$java_opts_file"
    else
      jruby_java_opts="$jruby_java_opts $(cat $java_opts_file)"
    fi
  fi
}

# Add local and global .jruby.java_opts
installed_jruby_java_opts_file="$JRUBY_HOME/bin/.jruby.java_opts"
home_jruby_java_opts_file="$HOME/.jruby.java_opts"
pwd_jruby_java_opts_file="$PWD/.jruby.java_opts"

unset jruby_java_opts
process_java_opts $installed_jruby_java_opts_file
process_java_opts $home_jruby_java_opts_file
process_java_opts $pwd_jruby_java_opts_file
JAVA_OPTS="$jruby_java_opts $JAVA_OPTS"

# space-separated list of special flags
JRUBY_OPTS_SPECIAL="--ng"
unset JRUBY_OPTS_TEMP
function process_special_opts {
    case $1 in
        --ng) nailgun_client=true;;
        *) break;;
    esac
}
for opt in ${JRUBY_OPTS[@]}; do
    for special in ${JRUBY_OPTS_SPECIAL[@]}; do
        if [ $opt != $special ]; then
            JRUBY_OPTS_TEMP="${JRUBY_OPTS_TEMP} $opt"
        else
            # make sure flags listed in JRUBY_OPTS_SPECIAL are processed
            case "$opt" in
            --ng)
                add_log "Enabling Nailgun client"
                process_special_opts $opt;;
            esac
        fi
    done
    if [ $opt == "-server" ]; then # JRUBY-4204
        add_log "Enabling -server mode"
        JAVA_VM="-server"
    fi
done
JRUBY_OPTS=${JRUBY_OPTS_TEMP}

if [ -z "$JAVA_STACK" ] ; then
  JAVA_STACK=-Xss2048k
fi

add_log "JAVA_STACK: $JAVA_STACK"

# Capture some Java options to be passed separately
unset JAVA_OPTS_TEMP
JAVA_OPTS_TEMP=""
for opt in ${JAVA_OPTS[@]}; do
  case $opt in
    -server)
      JAVA_VM="-server";;
    -Xmx*)
      JAVA_MEM=$opt;;
    -Xms*)
      JAVA_MEM_MIN=$opt;;
    -Xss*)
      JAVA_STACK=$opt;;
    *)
      JAVA_OPTS_TEMP="${JAVA_OPTS_TEMP} $opt";;
  esac
done

JAVA_OPTS=$JAVA_OPTS_TEMP


# If you're seeing odd exceptions, you may have a bad JVM install.
# Uncomment this and report the version to the JRuby team along with error.
#$JAVACMD -version

JRUBY_SHELL=/bin/sh

# ----- Set Up The Boot Classpath -------------------------------------------

CP_DELIMITER=":"

# add main jruby jar to the bootclasspath
for j in "$JRUBY_HOME"/lib/jruby.jar "$JRUBY_HOME"/lib/jruby-complete.jar; do
    if [ ! -e "$j" ]; then
      continue
    fi
    if [ "$JRUBY_CP" ]; then
        JRUBY_CP="$JRUBY_CP$CP_DELIMITER$j"
        else
        JRUBY_CP="$j"
    fi
    if [ $JRUBY_ALREADY_ADDED ]; then
        echo "WARNING: more than one JRuby JAR found in lib directory"
    fi
    JRUBY_ALREADY_ADDED=true
done

if $cygwin; then
    JRUBY_CP=`cygpath -p -w "$JRUBY_CP"`
fi

# ----- Set Up The System Classpath -------------------------------------------

if [ "$JRUBY_PARENT_CLASSPATH" != "" ]; then
    # Use same classpath propagated from parent jruby
    CP=$JRUBY_PARENT_CLASSPATH
else
    # add other jars in lib to CP for command-line execution
    for j in "$JRUBY_HOME"/lib/*.jar; do
        if [ "$j" == "$JRUBY_HOME"/lib/jruby.jar ]; then
          continue
        fi
        if [ "$j" == "$JRUBY_HOME"/lib/jruby-complete.jar ]; then
          continue
        fi
        if [ "$CP" ]; then
            CP="$CP$CP_DELIMITER$j"
            else
            CP="$j"
        fi
    done

    if [ "$CP" != "" ] && $cygwin; then
        CP=`cygpath -p -w "$CP"`
    fi
fi

if $cygwin; then
    # switch delimiter only after building Unix style classpaths
    CP_DELIMITER=";"
fi

# ----- Execute The Requested Command -----------------------------------------
JAVA_ENCODING=""

if [ -r "/dev/urandom" ]; then
  # OpenJDK tries really hard to prevent you from using urandom.
  # See https://bugs.openjdk.java.net/browse/JDK-6202721
  # Non-file URL causes fallback to slow threaded SeedGenerator.
  # See https://bz.apache.org/bugzilla/show_bug.cgi?id=56139
  JAVA_SECURITY_EGD="file:/dev/urandom"
fi

declare -a java_args
declare -a ruby_args
mode=""

JAVA_CLASS_JRUBY_MAIN=org.jruby.Main
java_class=$JAVA_CLASS_JRUBY_MAIN
JAVA_CLASS_NGSERVER=org.jruby.main.NailServerMain

# Options from .dev_mode.java_opts for "--dev" mode, to reduce JRuby startup time
dev_mode_opts_file="$JRUBY_HOME/bin/.dev_mode.java_opts"
if [[ $is_java9 ]]; then
  dev_mode_opts="@$dev_mode_opts_file"
else
  dev_mode_opts=`cat $dev_mode_opts_file`
fi

# Split out any -J argument for passing to the JVM.
# Scanning for args is aborted by '--'.
set -- $JRUBY_OPTS "$@"
add_log "JRuby command line options: $@"
while [ $# -gt 0 ]
do
    case "$1" in
    # Stuff after '-J' in this argument goes to JVM
    -J*)
        val=${1:2}
        if [ "${val:0:4}" = "-Xmx" ]; then
            JAVA_MEM=$val
        elif [ "${val:0:4}" = "-Xms" ]; then
            JAVA_MEM_MIN=$val
        elif [ "${val:0:4}" = "-Xss" ]; then
            JAVA_STACK=$val
        elif [ "${val}" = "" ]; then
            $JAVACMD -help
            echo "(Prepend -J in front of these options when using 'jruby' command)" 
            exit
        elif [ "${val}" = "-X" ]; then
            $JAVACMD -X
            echo "(Prepend -J in front of these options when using 'jruby' command)" 
            exit
        elif [ "${val}" = "-classpath" ]; then
            CP="$CP$CP_DELIMITER$2"
            CLASSPATH=""
            shift
        elif [ "${val}" = "-cp" ]; then
            CP="$CP$CP_DELIMITER$2"
            CLASSPATH=""
            shift
        else
            if [ "${val:0:3}" = "-ea" ]; then
                VERIFY_JRUBY="yes"
                java_args=("${java_args[@]}" "${1:2}")
            elif [ "${val:0:16}" = "-Dfile.encoding=" ]; then
                JAVA_ENCODING=${val:16}
            elif [ "${val:0:20}" = "-Djava.security.egd=" ]; then
                JAVA_SECURITY_EGD=${val:20}
            else
                java_args=("${java_args[@]}" "${1:2}")
            fi
        fi
        ;;
     # Pass -X... and -X? search options through
     -X*\.\.\.|-X*\?)
        ruby_args=("${ruby_args[@]}" "$1") ;;
     # Match -Xa.b.c=d to translate to -Da.b.c=d as a java option
     -X*)
        val=${1:2}
        if expr "$val" : '.*[.]' > /dev/null; then
          java_args=("${java_args[@]}" "-Djruby.${val}")
        else
          ruby_args=("${ruby_args[@]}" "-X${val}")
        fi
        ;;
     # Match switches that take an argument
     -C|-e|-I|-S) ruby_args=("${ruby_args[@]}" "$1" "$2"); shift ;;
     # Match same switches with argument stuck together
     -e*|-I*|-S*) ruby_args=("${ruby_args[@]}" "$1" ) ;;
     # Run with JMX management enabled
     --manage)
        java_args=("${java_args[@]}" "-Dcom.sun.management.jmxremote")
        java_args=("${java_args[@]}" "-Djruby.management.enabled=true") ;;
     # Don't launch a GUI window, no matter what
     --headless)
        java_args=("${java_args[@]}" "-Djava.awt.headless=true") ;;
     # Run under JDB
     --jdb)
        if [ -z "$JAVA_HOME" ] ; then
          JAVACMD='jdb'
        else
          if $cygwin; then
            JAVACMD="`cygpath -u "$JAVA_HOME"`/bin/jdb"
          else
            JAVACMD="$JAVA_HOME/bin/jdb"
          fi
        fi 
        JDB_SOURCEPATH="${JRUBY_HOME}/core/src/main/java:${JRUBY_HOME}/lib/ruby/stdlib:."
        java_args=("${java_args[@]}" "-sourcepath" "$JDB_SOURCEPATH")
        JRUBY_OPTS=("${JRUBY_OPTS[@]}" "-X+C") ;;
     --client)
        JAVA_VM=-client ;;
     --server)
        JAVA_VM=-server ;;
     --dev)
        JAVA_VM=-client
        JAVA_OPTS="$JAVA_OPTS $dev_mode_opts"
        add_log "Adding Java options from: $dev_mode_opts_file" ;;
     --noclient)         # JRUBY-4296
        unset JAVA_VM ;; # For IBM JVM, neither '-client' nor '-server' is applicable
     --sample)
        java_args=("${java_args[@]}" "-Xprof") ;;
     --record)
        java_args=("${java_args[@]}" "-XX:+FlightRecorder" "-XX:StartFlightRecording=dumponexit=true") ;;
     --ng-server)
        # Start up as Nailgun server
        java_class=$JAVA_CLASS_NGSERVER
        VERIFY_JRUBY=true ;;
     --no-bootclasspath)
        NO_BOOTCLASSPATH=true ;;
     --ng)
        # Use native Nailgun client to toss commands to server
        process_special_opts "--ng" ;;
     --environment) print_environment_log=1 ;;
     # warn but ignore
     --1.8) echo "warning: --1.8 ignored" ;;
     # warn but ignore
     --1.9) echo "warning: --1.9 ignored" ;;
     # warn but ignore
     --2.0) echo "warning: --1.9 ignored" ;;
     # Abort processing on the double dash
     --) break ;;
     # Other opts go to ruby
     -*) ruby_args=("${ruby_args[@]}" "$1") ;;
     # Abort processing on first non-opt arg
     *) break ;;
    esac
    shift
done

# Force file.encoding to UTF-8 when on Mac, since Apple JDK defaults to MacRoman (JRUBY-3576)
if [[ $darwin && -z "$JAVA_ENCODING" ]]; then
  java_args=("${java_args[@]}" "-Dfile.encoding=UTF-8")
elif [[ -n "$JAVA_ENCODING" ]]; then
  java_args=("${java_args[@]}" "-Dfile.encoding=$JAVA_ENCODING")
fi

# Force OpenJDK-based JVMs to use /dev/urandom for random number generation
# See https://github.com/jruby/jruby/issues/4685 among others.
if [[ -n "$JAVA_SECURITY_EGD" ]]; then
  java_args=("${java_args[@]}" "-Djava.security.egd=$JAVA_SECURITY_EGD")
fi

# Append the rest of the arguments
ruby_args=("${ruby_args[@]}" "$@")

# Put the ruby_args back into the position arguments $1, $2 etc
set -- "${ruby_args[@]}"

JAVA_OPTS="$JAVA_OPTS $JAVA_MEM $JAVA_MEM_MIN $JAVA_STACK"

JFFI_OPTS="-Djffi.boot.library.path=$JRUBY_HOME/lib/jni"

if $cygwin; then
  use_exec=false
  JRUBY_HOME=`cygpath --mixed "$JRUBY_HOME"`
  JRUBY_SHELL=`cygpath --mixed "$JRUBY_SHELL"`

  if [[ ( "${1:0:1}" = "/" ) && ( ( -f "$1" ) || ( -d "$1" )) ]]; then
    win_arg=`cygpath -w "$1"`
    shift
    win_args=("$win_arg" "$@")
    set -- "${win_args[@]}"
  fi

  # fix JLine to use UnixTerminal
  stty -icanon min 1 -echo > /dev/null 2>&1
  if [ $? = 0 ]; then
    JAVA_OPTS="$JAVA_OPTS -Djline.terminal=jline.UnixTerminal"
  fi

fi

# Allow overriding default JSA file location
if [ "$JRUBY_JSA" == "" ]; then
  JRUBY_JSA=${JRUBY_HOME}/lib/jruby.jsa
fi

# Determine whether to pass module-related flags
if [[ $is_java9 ]]; then
  # Use module path instead of classpath for the jruby libs
  classpath_args=(--module-path "$JRUBY_CP" -classpath "$CP$CP_DELIMITER$CLASSPATH")

  # Switch to non-boot path since we can't use bootclasspath on 9+
  NO_BOOTCLASSPATH=1

  # If we have a jruby.jsa file, enable AppCDS
  if [ -f $JRUBY_JSA ]; then
    add_log "AppCDS archive: $JRUBY_JSA"
    JAVA_OPTS="$JAVA_OPTS -XX:+UnlockDiagnosticVMOptions -XX:SharedArchiveFile=$JRUBY_JSA"
  fi

  # Add base opens we need for Ruby compatibility
  JAVA_OPTS="$JAVA_OPTS --add-opens java.base/java.io=org.jruby.dist --add-opens java.base/java.nio.channels=org.jruby.dist --add-opens java.base/sun.nio.ch=org.jruby.dist"
else
  classpath_args=(-classpath "$JRUBY_CP$CP_DELIMITER$CP$CP_DELIMITER$CLASSPATH")
fi

# Run JRuby!
if [ "$nailgun_client" != "" ]; then

  if [ -f $JRUBY_HOME/tool/nailgun/ng ]; then
    jvm_command=$JRUBY_HOME/tool/nailgun/ng org.jruby.util.NailMain $mode "$@"
  else
    echo "error: ng executable not found; run 'make' in ${JRUBY_HOME}/tool/nailgun"
    exit 1
  fi

elif [[ "$NO_BOOTCLASSPATH" != "" || "$VERIFY_JRUBY" != "" ]]; then

  if [[ "${java_class:-}" == "${JAVA_CLASS_NGSERVER:-}" && -n "${JRUBY_OPTS:-}" ]]; then
    echo "warning: starting a nailgun server; discarding JRUBY_OPTS: ${JRUBY_OPTS}"
    use_exec=false
    JRUBY_OPTS=''
  fi

  jvm_command=("$JAVACMD" $JAVA_OPTS "$JFFI_OPTS" "${java_args[@]}" "${classpath_args[@]}" \
    "-Djruby.home=$JRUBY_HOME" \
    "-Djruby.lib=$JRUBY_HOME/lib" -Djruby.script=jruby \
    "-Djruby.shell=$JRUBY_SHELL" \
    $java_class $mode "$@")

else

  jvm_command=("$JAVACMD" $JAVA_OPTS "$JFFI_OPTS" "${java_args[@]}" -Xbootclasspath/a:"$JRUBY_CP" -classpath "$CP$CP_DELIMITER$CLASSPATH" \
    "-Djruby.home=$JRUBY_HOME" \
    "-Djruby.lib=$JRUBY_HOME/lib" -Djruby.script=jruby \
    "-Djruby.shell=$JRUBY_SHELL" \
    $java_class $mode "$@")

fi

full_java_command="${jvm_command[@]}"
add_log "Full Java command line: $full_java_command"

if [[ $print_environment_log ]]; then
  echo "$environment_log"
  exit 0
fi

# Run JRuby!
if $use_exec; then
  exec "${jvm_command[@]}"
else
  "${jvm_command[@]}"

  # Record the exit status immediately, or it will be overridden.
  JRUBY_STATUS=$?

  if $cygwin; then
    stty icanon echo > /dev/null 2>&1
  fi

  exit $JRUBY_STATUS
fi
