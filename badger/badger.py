import pathlib
import subprocess
import tempfile
import shutil
import sys

BADGES = {
    "python": "![Python](https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white)",
    "pytorch": "![PyTorch](https://img.shields.io/badge/PyTorch-EE4C2C?logo=pytorch&logoColor=white)",
    "docker": "![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)",
    "kubernetes": "![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)",
    "solidity": "![Solidity](https://img.shields.io/badge/Solidity-363636?logo=solidity&logoColor=white)",
}

RULES = {
    "python": [".py", "requirements.txt", "pyproject.toml"],
    "pytorch": ["torch", "pytorch"],
    "docker": ["dockerfile", "docker-compose.yml"],
    "kubernetes": ["k8s", "deployment.yaml", "helm"],
    "solidity": [".sol", "hardhat.config.js", "foundry.toml"],
}

def clone_repo(repo_url: str) -> pathlib.Path:
    tmp_dir = tempfile.mkdtemp(prefix="stackscan_")
    subprocess.run(
        ["git", "clone", "--depth", "1", repo_url, tmp_dir],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return pathlib.Path(tmp_dir)

def scan_repo(path: pathlib.Path):
    found = set()
    files = [p for p in path.rglob("*") if p.is_file()]

    for tech, patterns in RULES.items():
        for f in files:
            fname = f.name.lower()
            for p in patterns:
                if p in fname:
                    found.add(tech)
    return found

def generate_markdown(found):
    md = ["## Detected Tech Stack\n"]
    for tech in sorted(found):
        md.append(BADGES.get(tech, f"- {tech}"))
    return "\n".join(md)

def main():
    if len(sys.argv) != 2:
        print("Usage: python scan.py <git_repo_url>")
        sys.exit(1)

    repo_url = sys.argv[1]
    repo_path = None

    try:
        repo_path = clone_repo(repo_url)
        tech = scan_repo(repo_path)
        print(generate_markdown(tech))
    finally:
        if repo_path and repo_path.exists():
            shutil.rmtree(repo_path)

if __name__ == "__main__":
    main()
