#!/bin/bash

# Liste der Laufwerke, die überprüft werden sollen
DRIVES=("/dev/sda" "/dev/sdb")

# E-Mail-Details
EMAIL="deine-email@outlook.com"
SUBJECT="SMART Fehler auf einem Laufwerk"
FROM="deine-email@outlook.com"

# Schleife über jedes Laufwerk in der Liste
for DRIVE in "${DRIVES[@]}"; do
    # Führe den SMART-Test aus und überprüfe das Ergebnis
    SMART_RESULT=$(smartctl -H $DRIVE | grep -i "overall-health" | awk '{print $6}')
    
    # Wenn das Ergebnis nicht "PASSED" ist, sende eine E-Mail
    if [[ "$SMART_RESULT" != "PASSED" ]]; then
        MESSAGE="Warnung: SMART-Status von $DRIVE ist nicht OK. Status: $SMART_RESULT"
        
        # Verwende printf, um die E-Mail korrekt zu formatieren
        printf "Subject: $SUBJECT\nFrom: $FROM\nTo: $EMAIL\n\n$MESSAGE\n" | msmtp $EMAIL
    fi
done
