#!/bin/bash
# clean_unused_image_to_recover_space.sh
# Script per la rimozione sicura delle immagini non in uso da containerd in MicroK8s.

# 1. Otteniamo tutte le immagini usate attualmente dai Pod attivi
echo "1. Ricerca immagini in uso dai pod..."
# Usiamo jsonpath per estrarre sia le immagini dei container normali che degli initContainer
IN_USE_IMAGES=$(microk8s kubectl get pods -A -o jsonpath="{.items[*].spec.containers[*].image} {.items[*].spec.initContainers[*].image}" | tr ' ' '\n' | sort | uniq)

IN_USE_COUNT=$(echo "$IN_USE_IMAGES" | grep -v '^$' | wc -l)
echo "-> Trovate $IN_USE_COUNT immagini uniche attualmente in uso."

# 2. Otteniamo tutte le immagini memorizzate in containerd (namespace k8s.io)
echo "2. Lettura di tutte le immagini archiviate in containerd..."
ALL_IMAGES=$(microk8s ctr --namespace k8s.io images ls | awk 'NR>1 {print $1}' | sort | uniq)

ALL_COUNT=$(echo "$ALL_IMAGES" | grep -v '^$' | wc -l)
echo "-> Trovate $ALL_COUNT immagini salvate nel nodo."

# 3. Calcolo della differenza (orfanate) usando 'comm'
echo "3. Calcolo orfani..."
IMAGES_TO_DELETE=$(comm -23 <(echo "$ALL_IMAGES") <(echo "$IN_USE_IMAGES"))

DELETE_COUNT=$(echo "$IMAGES_TO_DELETE" | grep -v '^$' | wc -l)

if [ "$DELETE_COUNT" -eq 0 ]; then
    echo "Nessuna immagine orfana da eliminare. Pulizia terminata."
    exit 0
fi

echo "Ci sono $DELETE_COUNT immagini non in uso da cancellare."

# 4. Cancellazione sicura iterando sulla lista orfana
echo "4. Inizio cancellazione..."
FREED_COUNT=0
for img in $IMAGES_TO_DELETE; do
    if [ -n "$img" ]; then
        echo " - Eliminazione: $img"
        microk8s ctr --namespace k8s.io images rm "$img"
        if [ $? -eq 0 ]; then
            FREED_COUNT=$((FREED_COUNT+1))
        fi
    fi
done

echo "Pulizia terminata. Eliminate $FREED_COUNT immagini."
