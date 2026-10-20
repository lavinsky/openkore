# Status de implementação — OpenKore Visual Behavior Tree

Atualizado em 2026-10-20. Branch `feat/visual-behavior-tree`, baseline `7869ea85d`. Todo trabalho desta implementação está restrito a `plugins/visualBehaviorTree/`, `control/behaviorTree/` e este documento. `src/` e plugins preexistentes não foram modificados. O plugin não foi ativado em `control/sys.txt`.

## Fases

- [x] **Fase 0 — baseline:** branch limpa; inventariados `mainLoop_pre`, `AI_pre`, `AI_pre/manual`, `Plugins::addHooks/delHooks`, `Commands::register/unregister`, APIs de percentual de personagem e limites de confirmação de tarefas. Baseline não tinha testes para este recurso. Sem instância de jogo ou credenciais executada.
- [x] **Fase 1 — núcleo puro:** catálogo JSON compartilhado; validação estrutural e semântica em Perl; seletor prioritário reativo, sequência com rechecagem de guardas, fallback, decoradores, condições e espera não bloqueante; testes Test::More.
- [x] **Fase 2 — plugin shadow:** hooks e comando `bt`, recarga validada de implantação, status/eventos sanitizados, tick limitado a 10 Hz e `shadow` forçado. Sem despacho de ação nem alteração de config.
- [~] **Fase 3 — editor/API:** app React + TypeScript + `@xyflow/react`, paleta/inspector baseado no catálogo, canvas e conexões, histórico, prioridade, validação, simulador Perl, rascunhos com ETag, publicação atômica/rollback, serviço com bearer token localhost, verificação Origin/Host, rate limit e limites de corpo. Falta E2E e uso real no navegador.
- [ ] **Fase 4 — assistido:** ações nativas não habilitadas; requer contrato de conclusão e ownership comprovado por ação.
- [ ] **Fase 5 — combate/Kafra/managed:** bloqueada até validação live e implementação de overlays reversíveis em memória.
- [~] **Fase 6 — entrega:** documentação operacional e exemplos presentes; importação, benchmark, Windows, auditoria de conflitos e fuzz extensivo pendentes.

## Evidência registrada

- Teste de núcleo: `perl -Iplugins/visualBehaviorTree/lib plugins/visualBehaviorTree/t/00-core.t` — 15 asserções passaram.
- UI: `npm run build` passou; `npm test` passou com 3 testes Vitest e 1 teste de API condicional ignorado.
- API integration não executou: sandbox retornou `listen EPERM` ao bindar `127.0.0.1`; o caso é ignorado com motivo explícito. Não há alegação de auth/CRUD testados por HTTP neste ambiente.
- `perl -I/tmp/vbt-stubs -Iplugins/visualBehaviorTree/lib -c plugins/visualBehaviorTree/visualBehaviorTree.pl` passou com stubs para isolar sintaxe. A compilação contra os módulos completos de `src/` foi bloqueada pela dependência ausente `Exception::Class` em `src/FastUtils.pm`.
- `perl -Iplugins/visualBehaviorTree/lib -c plugins/visualBehaviorTree/bin/simulate.pl`, parse JSON do catálogo e `node --check .../server/index.mjs` passaram.
- `git diff --exit-code -- src plugins control/sys.txt control/config.txt` passou; nenhuma instalação OpenKore externa foi tocada.
- O simulador chama somente `perl plugins/visualBehaviorTree/bin/simulate.pl`; não recebe caminho ou comando externo do usuário.
- Revisão de API OpenKore: `src/Plugins.pm` documenta hooks/handles, `src/Commands.pm` confirma a assinatura de registro, `src/Actor/You.pm` expõe `hp_percent`, `sp_percent`, `weight_percent`.

## Limitações que afetam prontidão

- **Não é pronto para controlar personagem.** Todas as ações reais, `assist`, `managed` e overrides estão recusados; shadow é obrigatório na publicação.
- Snapshot OpenKore parcial: agressividade, LOS, estado sentado, inventário, posição, status, fila e conexão detalhada não são inferidos. Condições sem sensor geram `ERROR`.
- Falta testar integração carregando plugin, três reloads, evento de conclusão de storage, tarefas de ataque/rota/sit/teleporte e reconexões. Não foi iniciada sessão de jogo.
- Editor depende de Node/npm; `package-lock.json` foi gerado com sucesso via `npm install --offline` e buildado localmente. Build gerado fica fora do controle de versão; o launcher compila na instalação.
- Alguns itens do capítulo 15 ainda não atendidos: acessibilidade auditada, E2E, simulação igual ao runtime para todos os nós, eventos de runtime alinhados por cursor e validação de 256 KiB no perfil node (há limite HTTP e Perl).

## Próximos passos seguros

1. Executar `npm install`, build e testes Vitest; corrigir falhas e manter lockfile versionado.
2. Exercitar API em diretório de controle temporário e cobrir auth, Origin, If-Match, rollback, atomicidade, path traversal e corpo excessivo.
3. Escrever mocks de ciclo do plugin e completar snapshot somente com APIs confirmadas.
4. Integrar ações individualmente e obter validação do usuário antes de qualquer ação live; até lá manter recursos bloqueados.
