set -u
getProperties="getprop"
productBoardPropertyName="ro.product.board"
pathToInitFiles=""
pathToOverlayFiles="overlay.d"
magicOptionsToDisableBootToCharge="    class_stop charger \n    trigger late-init"
occPrefix="/data/adb/on-charge-controller-data/logs"
logFile="${occPrefix}/on-charge-controller.log"

log() {
	if [[ ! -f "$logFile" ]]; then
		touch "$logFile"
	fi
	echo "$(date '+%Y-%m-%d_%H:%M:%S')|${2:-"INF"}|${1}" >> "$logFile"
}

getProductBoard() {
	local productBoard=$(${getProperties} ${productBoardPropertyName}) || exit 4
	log "Detected product board ${productBoard}"
	echo ${productBoard}
}

checkProductBoardInitFile() {
	local productBoardInitFile=$1
	if [[ -f ${productBoardInitFile} ]]; then
		log "Product board init file ${productBoardInitFile} present"
	else
		log "No such file: ${productBoardInitFile}" ERR && exit 5
	fi
}

findOnChargerLine() {
	local onBoardInitFileContent="${1}"
	local line=$(echo "$onBoardInitFileContent" | grep -n 'on charger' | grep -o '^[0-9]*')
	if [[ -z ${line} ]]; then
		log "No on charger found in $onBoardInitFileContent" ERR 
		exit 13
	else
		log "onChargerLineNumber = ${line}" DBG
	fi
	echo "${line}"
}

findNextGroupLine() {
	local onChargerLineNumber="$1"
	local onBoardInitFileContent="$2"
	local nextGroupLine=0
	local lines=$(echo "$onBoardInitFileContent" | grep -n '^on ' | grep -o '^[0-9]*')
# 	log "^on  lines = ${lines}" DBG
	for lineNr in ${lines}; do
		if [[ $lineNr -gt $onChargerLineNumber ]]; then
			nextGroupLine=$lineNr
			break
		fi
	done
	log "nextGroupLine = ${nextGroupLine}" DBG
	echo "${nextGroupLine}"
}

insertMagicTextBeforeNextGroup() {
	local startLine=$((${1} - 1))
	onBoardInitFileContent="${2}"
	
	if [[ $startLine -lt 0 ]]; then
		startLine=0
	fi
	log "start line: $startLine"
	local boardInitFileChangedContent="$(echo "$onBoardInitFileContent" | sed "${startLine}i\\${magicOptionsToDisableBootToCharge}")"
	echo "${boardInitFileChangedContent}"
}

getProductBoardFileContent() {
	local productBoardInitFilePath="${1}"
	local onBoardInitFileContent="$(cat "${productBoardInitFilePath}")" || exit 40
	if [[ -z ${onBoardInitFileContent} ]]; then
		log "Empty $onBoardInitFileContent" ERR
		exit 14
	else
		log "board init file has length = ${#onBoardInitFileContent}" DBG
	fi
	echo "${onBoardInitFileContent}"
}

changeBoardInitFile() {
	onBoardInitFileContent="${1}"
	local onChargerLineNumber=$(findOnChargerLine "${onBoardInitFileContent}")
	local nextGroupLine=$(findNextGroupLine ${onChargerLineNumber} "${onBoardInitFileContent}")
	log "changeBoardInitFile() nextGroupLine: ${nextGroupLine}"
	echo $(insertMagicTextBeforeNextGroup "${nextGroupLine}" "${onBoardInitFileContent}")
}

overrideInitFiles() {
	local fileContent="${1}"
	local fileToBeWritten="${2}"
	log "writing changes to: ${fileToBeWritten}"
	echo "${fileContent}" > "${fileToBeWritten}" || exit 4
}

productBoard=$(getProductBoard)
productBoardInitFile="init.${productBoard}.rc"
productBoardInitFilePath="${pathToInitFiles}/${productBoardInitFile}"
checkProductBoardInitFile ${productBoardInitFilePath}
onBoardInitFileContent="$(getProductBoardFileContent "${productBoardInitFilePath}")"
boardInitFileChangedContent=$(changeBoardInitFile "${onBoardInitFileContent}")
if [[ ! -d "${pathToOverlayFiles}" ]]; then
	mkdir "${pathToOverlayFiles}" || exit 44
fi
overrideInitFiles "${boardInitFileChangedContent}" "${pathToOverlayFiles}/${productBoardInitFile}"
log "All done" INF
