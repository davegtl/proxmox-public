Make sure link is up
sudo ip link set ens19 up

install dchp
sudo apt-get update
sudo apt-get install -y dnsmasq



kubectl delete pod test-vlan50 -n webservices
kubectl apply -f test-vlan50.yaml

kubectl exec -n webservices test-vlan50 -- ip a

kubectl describe pod test-vlan50 -n webservices

sudo nano /etc/systemd/system/cni-dhcp.service
[Unit]
Description=CNI DHCP Daemon
After=network.target

[Service]
ExecStart=/opt/cni/bin/dhcp daemon
Restart=always

[Install]
WantedBy=multi-user.target

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now cni-dhcp







examples

#homeassistant-net.yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: homeassistant
  namespace: webservices
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "macvlan",
      "master": "ens19",
      "mode": "bridge",
      "vlan": 50,
      "ipam": {
        "type": "static"
      }
    }

#homeassistant-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: homeassistant
  namespace: webservices
  annotations:
    k8s.v1.cni.cncf.io/networks: |
      [{
        "name": "webservices/homeassistant",
        "ips": ["10.0.50.102"]
      }]
spec:
  containers:
  - name: homeassistant
    image: busybox
    command: ["sleep", "3600"]
