# Mapsim Tunnel Manager

A WireGuard tunnel management script to create and manage a WireGuard interface named `wg1`,  
with the ability to automatically add external servers (peers) via SSH and fully manage them.

---

## Features

- Automatic installation of the main WireGuard server  
- Add external servers (Distance Servers) with SSH connection and WireGuard configuration  
- List registered external servers  
- Remove external servers and clean up completely  
- Remove the main server entirely  
- Display the service and peers status in a colorful and neat way

---

## Requirements

- Operating System: Ubuntu or Debian  
- Root access to run the script  
- The following packages will be installed automatically if missing:  
  - wireguard  
  - wireguard-tools  
  - jq  
  - sshpass  
  - resolvconf  
  - iptables

---

## Installation and Usage

---

### Automatic method (without menu)

You can call functions inside the script from another shell script or directly execute commands.  
For example, to install the main server automatically:

```bash
sudo bash -c "$(curl -fsSL https://github.com/MAPSIM-co/Mapsim_Wireguard_Tunnel/main/mapsim-tunnel.sh)"
```

(Note: Adjust the URL and usage as per your setup)

---

### Manual method

1. Copy the script to your server or clone the repository.  
2. Make the script executable:

```bash
chmod +x mapsim-tunnel.sh
```

3. Run the script as root:

```bash
sudo ./mapsim-tunnel.sh
```

4. An interactive menu will appear, allowing you to choose installation, add external servers, and more.

---

## Important Notes

- SSH passwords for external servers are securely prompted and used for SSH connections.  
- Internal tunnel IPs and other configurations can be modified in the variables at the top of the script.  
- Always make sure you do not lose critical connections before removing main or external servers.

---

## License

This project is licensed under the [MIT](https://github.com/MAPSIM-co/Mapsim_Wireguard_Tunnel/blob/main/LICENSE) License.

---

## Contribution

If you have suggestions or find issues, please submit a Pull Request or open an issue.
