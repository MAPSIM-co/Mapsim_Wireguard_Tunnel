# Mapsim Tunnel Manager

A WireGuard tunnel management script to create and manage a WireGuard interface named `wg1`,  
with the ability to automatically add external servers (peers) via SSH and fully manage them.

---

## Usage Model

-  This tunnel management script must be run on the ``main server`` (e.g., the server located in Iran).

-  External servers, called ``Distance Servers``, are the remote peers (e.g., foreign servers)
  
-  **that connect to the main server via WireGuard tunnels.**

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
  - recommend using ``Ubuntu 22.04``
- Root access to run the script  
- The following packages will be installed automatically if missing:  
  - wireguard  
  - wireguard-tools  
  - jq  
  - sshpass  
  - resolvconf  
  - iptables

---

## Logo Script

![Logo Script](https://github.com/MAPSIM-co/Mapsim_Wireguard_Tunnel/blob/main/Image/Mapsim_logo.png?raw=true)


---

## Installation and Usage

---

### Automatic Install

You can call functions inside the script from another shell script or directly execute commands.  
For example, to install the main server automatically:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/MAPSIM-co/Mapsim_Wireguard_Tunnel/main/install.sh)"

```

(Note: Adjust the URL and usage as per your setup)

---

### Manual Method

1. Copy the script to your server or clone the repository:
   ```bash
   git clone https://github.com/MAPSIM-co/Mapsim_Wireguard_Tunnel.git
   cd Mapsim_Wireguard_Tunnel
    ```
   
2. Make the script executable:
   ```bash
   chmod +x mapsim-tunnel.sh
   ```
   
4. Run the script as root:
   ```bash
   sudo ./mapsim-tunnel.sh
   ```
  - if ``root`` :

     ```bash
     sudo mapsim-tunnel.sh
     ```

**An interactive menu will appear, allowing you to:**

- **Install the Mapsim tunnel service**
- **Add or remove external servers (``reverse tunnels``)**
- **Start/stop the tunnel**
- **Check tunnel and peer status**

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
