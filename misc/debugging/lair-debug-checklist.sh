#!/bin/bash

echo "=== LAIR DEBUGGING CHECKLIST ==="
echo "Use this checklist to systematically debug issues"
echo

echo "□ 1. Cluster connectivity (kubectl cluster-info)"
echo "□ 2. Node status (kubectl get nodes)"
echo "□ 3. Pod status (kubectl get pods -n lair)"
echo "□ 4. Service status (kubectl get services -n lair)"
echo "□ 5. Ingress status (kubectl get ingress -n lair)"
echo "□ 6. Recent events (kubectl get events -n lair)"
echo "□ 7. Resource usage (kubectl top pods -n lair)"
echo "□ 8. Application logs (kubectl logs -n lair <pod-name>)"
echo "□ 9. Service connectivity (curl tests between services)"
echo "□ 10. DNS resolution (nslookup tests)"
echo "□ 11. Storage status (kubectl get pvc -n lair)"
echo "□ 12. Certificate status (kubectl get certificates -n lair)"
echo "□ 13. Network policies (kubectl get networkpolicies -n lair)"
echo "□ 14. External connectivity (ping, curl external services)"
echo "□ 15. System resources (df -h, free -h, uptime)"
echo

echo "Run specific debug scripts:"
echo "- Emergency debug: ./misc/debugging/lair-emergency-debug.sh"
echo "- Full debug logs: ./misc/debugging/lair-debug-logs.sh"
echo "- Network debug: ./misc/debugging/lair-network-debug.sh"
echo "- OpenWebUI debug: ./misc/debugging/lair-openwebui-debug.sh"
echo "- Ollama debug: ./misc/debugging/lair-ollama-debug.sh"