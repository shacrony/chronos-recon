#  Bug Bounty Recon Toolkit

Automatação de enumeração de subdomínios, verificação de serviços ativos, coleta de URLs, fuzzing e detecção de **Subdomain Takeover** ferramenta de recon robusta criada especialmente para Bug Bounty e Pentest.

---

##  Estrutura

O script `chronos-recon.sh` cria uma pasta com o nome `recon-DOMINIO-DATA`, contendo todos os resultados organizados por tipo de teste. Ele utiliza as melhores ferramentas para realizar as tarefas de forma eficiente e paralela.

---


## Pré-requisitos:

## Você deve ter as seguintes ferramentas instaladas:

sublist3r

subfinder

chaos

httpx-toolkit

nuclei

katana

gf

dirsearch

waybackurls

GitDorker

Python 3 + takeover.py (fornecido neste repositório)

Também é necessário definir a variável de ambiente da Chaos API:

export CHAOS_KEY=suachaveaqui

## Como usar

```bash
chmod +x recon.sh
./chronos-recon.sh exemplo.com

