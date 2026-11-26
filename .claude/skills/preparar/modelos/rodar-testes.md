---
name: rodar-testes
description: Como rodar, escrever e depurar testes neste projeto. Usar ao rodar a pilha de testes, investigar um teste que falha ou criar um teste novo.
---

## Rodar

- Pilha completa: `<comando>`
- Um arquivo: `<comando>`
- Um teste pelo nome: `<comando>`
- Tempo esperado da pilha completa: <minutos>

Dentro do `/fluxo`, a pilha completa roda pelo comando da pilha que vem no despacho, e não direto: ele grava o resultado e não repete a rodada sobre código que já tem resultado.

## Escrever

- Onde ficam os testes de cada tipo: <pastas>
- Como nomear arquivo e teste: <padrão>
- Dados de teste e fábricas prontas: <onde estão e como usar>
- O que nunca usar em teste: <rede real, relógio real, banco compartilhado>

## Depurar

- Ver a saída completa de um teste: `<comando ou opção>`
- Falhas conhecidas que não são defeito do código:
  - <sintoma>: <causa e como contornar>

## Antes de dizer que passou

Rode a pilha completa, não só o arquivo em que você mexeu, e copie a linha de resumo da saída.
