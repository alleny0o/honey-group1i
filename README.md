# Honeypot System Documentation

## Overview
The system uses containerization (LXC) to create honeypots with different banners and configurations. Each honeypot is monitored for attacker interactions and automatically recycled after a set period.

## Core Scripts

### init.sh
The main initialization script that bootstraps the entire system:
- Resets iptables rules and cleans up existing containers
- Creates a template container with basic configurations
- Deploys 4 honeypot containers with different banners (ethical, legal, technical, none)
- Sets up SSH, firewalls, and MITM servers for each container
- Configures networking and NAT rules
- Launches monitoring processes

### recycle_v2.sh
Handles container recycling operations:
- Removes existing containers and associated rules
- Creates new containers with randomized banners
- Sets up fresh MITM servers and networking rules
- Deploys honey files and configurations
- Updates firewall and SSH settings

### attacker_status.sh
Monitors honeypot interactions:
- Watches authentication attempt logs
- Detects new attacker IPs
- Updates iptables rules to isolate attacker traffic
- Triggers container recycling timer
- Maintains logging of attacker activities

### timer.sh
Manages container lifecycle:
- Implements countdown for container recycling
- Triggers recycle_v2.sh after countdown expires
- Ensures continuous rotation of honeypots

### reset.sh
System reset utility:
- Restores iptables to default state
- Cleans up all containers and PM2 processes

## Key Features
- Automated deployment and recycling
- Dynamic attacker isolation
- Multiple honeypot personalities (different SSH banners)
- MITM monitoring of attacker interactions
- Automatic IP and port management

## Workflow
1. `init.sh` bootstraps the system
2. `attacker_status.sh` monitors for connections
3. Upon detection, `timer.sh` starts countdown
4. `recycle_v2.sh` rotates containers after timeout
5. Process repeats automatically

## Security Considerations
- Each container is isolated
- Attacker traffic is contained
- Regular recycling prevents persistent compromise
- Honey files for attacker tracking
- Firewall rules automatically update for new attackers
