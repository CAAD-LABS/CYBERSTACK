---
name: verificar-tela
description: Como subir a aplicação com dados de exemplo e percorrer uma tela pelo navegador neste projeto. Usar ao verificar uma feature pela interface.
---

## Subir

1. Na pasta do código a verificar, carregue os dados de exemplo: `<comando>`
2. Suba a aplicação em uma porta livre: `<comando, com o lugar da porta>`
3. Pronto quando: <o que aparece na saída ou qual endereço responde>

## Entrar

- Endereço inicial: `http://localhost:<porta>/<caminho>`
- Contas de teste: <arquivo onde estão>. Use a conta do tipo de usuário que o critério de aceite descreve.
- Passos do login: <campos e botão>

## Navegar

- Menu principal: <onde fica e como abrir>
- Telas que demoram a carregar: <quais e o que esperar antes de agir>
- Tela pequena: largura de <pixels>

## Capturas

- Uma por passo do roteiro, nomeada `passo-<número>.png`, na pasta `capturas` dos artefatos da tarefa.

## Derrubar

- Encerre a aplicação: `<comando>`
- Volte os dados ao estado limpo: `<comando>`
