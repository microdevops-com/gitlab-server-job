#!/bin/bash

cd alive_minions

# Show all master / minion / count pairs
echo Alive Minions per Master:
for F in *; do
	echo $F
	cat $F
done

# Check at least one master has one needed minion
if cat *_${SALT_MINION} | grep -q 1; then
	echo OK: Master with 1 needed Minion found
else
	echo ERROR: Master with 1 needed Minion NOT found
	exit 1
fi
