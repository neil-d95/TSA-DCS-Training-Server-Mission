import json
import matplotlib.pyplot as plt
import requests
from datetime import datetime

WEBHOOK_URL = ""
JSON_FILE = r"C:\Users\YourName\Saved Games\DCS\Logs\carrier_discord.json"

# Load the JSON payload
with open(JSON_FILE, "r") as f:
    data = json.load(f)

landings = data.get("landings", {})

for player, traps in landings.items():
    # Create graph of approach
    xs = [trap["position"]["x"] for trap in traps]
    zs = [trap["position"]["z"] for trap in traps]  # altitude

    plt.figure(figsize=(6,4))
    plt.plot(xs, zs, marker='o', label=player)
    plt.axhline(0, linestyle='--', color='gray', label="Deck Level")
    plt.title(f"{player} Carrier Approach")
    plt.xlabel("Distance from Carrier (m)")
    plt.ylabel("Altitude (m)")
    plt.legend()
    graph_file = f"{player}_trap.png"
    plt.savefig(graph_file)
    plt.close()

    # Prepare Discord embed
    latest_trap = traps[-1]
    grade = latest_trap["grade"]
    wires = latest_trap["wires"]
    carrier = latest_trap["carrier"]
    timestamp = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

    content = f"**Carrier Trap Report**\n{player} landed on {carrier} at {timestamp}\nGrade: {grade} | Wire: {wires}"

    # Send to Discord with graph
    with open(graph_file, "rb") as f:
        requests.post(
            WEBHOOK_URL,
            data={"content": content},
            files={"file": f}
        )
