# Status de implementação — OpenKore Visual Behavior Tree

Atualizado em 2026-10-20. Branch `feat/visual-behavior-tree`, baseline `24456169c`. Todo trabalho desta implementação está restrito a `plugins/visualBehaviorTree/`, `control/behaviorTree/` e este documento. `src/` e plugins preexistentes não foram modificados. O plugin não foi ativado em `control/sys.txt`.

## Fases

- [x] **Fase 0 — baseline:** branch limpa; inventariados `mainLoop_pre`, `AI_pre`, `AI_pre/manual`, `Plugins::addHooks/delHooks`, `Commands::register/unregister`, APIs de percentual de personagem e limites de confirmação de tarefas. Baseline não tinha testes para este recurso. Sem instância de jogo ou credenciais executada.
- [x] **Fase 1 — núcleo puro:** catálogo JSON compartilhado; validação estrutural e semântica em Perl; seletor prioritário reativo, sequência com rechecagem de guardas, fallback, decoradores, condições e espera não bloqueante; testes Test::More.
- [x] **Fase 2 — plugin shadow:** hooks e comando `bt`, recarga validada de implantação, status/eventos sanitizados e tick limitado a 10 Hz. Shadow é o padrão; assist exige opt-in explícito.
- [~] **Fase 3 — editor/API:** app React + TypeScript + `@xyflow/react`, paleta/inspector baseado no catálogo, canvas e conexões, histórico, prioridade, validação, simulador Perl, rascunhos com ETag, publicação atômica/rollback, serviço com bearer token localhost, verificação Origin/Host, rate limit e limites de corpo. Falta E2E e uso real no navegador.
- [~] **Fase 4 — contrato assíncrono e bridge de leitura (parcial):** `Engine.pm` aceita adapter injetado; `NativeTasks.pm` cria tarefas OpenKore reais e as adiciona via `AI::queue`, conserva a referência exata e só remove o par ação/argumento que ainda corresponde a ela. O despacho exige configuração manual `visualBT_enableNativeTasks`, AI AUTO, conexão IN_GAME, personagem/campo disponíveis, personagem vivo e filas AI vazias; o padrão continua shadow. `Stand` e `Sit` exigem `Task::DONE` sem erro e estado sentado confirmado; `MoveOneTile` exige destino exato; `MoveTo` (somente mapa atual) exige coordenadas de destino; `TeleportRandom` exige confirmação da tarefa e mudança de mapa **ou** de coordenadas, incluindo Fly Wing dentro do mesmo mapa. Movimento de uma célula só é solicitado para tiles alcançáveis; sucesso exige posição observada real, não apenas `pos_to`. Falta a validação em uma sessão real; não executar o jogo. `StoreAtKafra`, `RestUntil`, `AttackTarget`, `UseItem` e `UseSkill` não são suportados e são recusados sem enfileirar tarefa. `OpenKoreReader.pm` e `OpenKoreSensors.pm` fornecem snapshot sanitizado com sensores conservadores de mobs/LOS e divisão entre atacando-me e tipo agressivo.
- [ ] **Fase 5 — combate/Kafra/managed:** não implementada. Managed continua rejeitado; combate, Kafra, overlays de configuração e adapters para itens/skills exigem handles/eventos comprovados e testes de integração.
- [~] **Fase 6 — entrega:** documentação operacional e exemplos presentes; importação, benchmark, Windows, auditoria de conflitos e fuzz extensivo pendentes.

## Evidência registrada

- Contrato assíncrono/snapshot/bridge: `perl -Iplugins/visualBehaviorTree/lib plugins/visualBehaviorTree/t/00-core.t` — 38 asserções Test::More passaram (adapter multi-tick, timeout, preempção, sanitização/readiness, leitura mock e capabilities desativadas).
- `OpenKoreReader.pm`, `OpenKoreSensors.pm`, `NativeTasks.pm` e `OpenKoreAdapter.pm` compilam isoladamente. O plugin passou em sintaxe com stubs de módulos OpenKore; reload hooks ainda não foram exercitados com jogo ativo.

- Teste de tarefas nativas: `perl plugins/visualBehaviorTree/t/01-native-tasks.t` — **37 asserções** passaram (fila exata, cancelamento isolado, auto-movimento, teleporte no mesmo mapa, bloqueios).
- Teste de sensores de monstros: `perl plugins/visualBehaviorTree/t/02-sensors.t` — **11 asserções** passaram (LOS, atacante, classificação por tipo e dados ausentes).
- UI: `npm run build` passou; `npm test` passou com **5 testes Vitest**, incluindo o teste de API HTTP local executado no Bazzite fora do sandbox.
- API: script de integração externo ao sandbox executado diretamente no Bazzite, com **16 verificações HTTP passando**: token, Origin, catálogo, validação Perl, ETag, salvamento, simulação, publicação shadow e limites de segurança. Script de teste local `/tmp/test_openkore_visualbt_api.py` (não versionado).
- `perl -I/tmp/vbt-stubs -Iplugins/visualBehaviorTree/lib -c plugins/visualBehaviorTree/visualBehaviorTree.pl` passou com stubs para isolar sintaxe. A compilação contra os módulos completos de `src/` foi bloqueada pela dependência ausente `Exception::Class` em `src/FastUtils.pm`.
- `perl -Iplugins/visualBehaviorTree/lib -c plugins/visualBehaviorTree/bin/simulate.pl`, parse JSON do catálogo e `node --check .../server/index.mjs` passaram.
- `git diff --exit-code -- src plugins control/sys.txt control/config.txt` passou; nenhuma instalação OpenKore externa foi tocada.
- O simulador chama somente `perl plugins/visualBehaviorTree/bin/simulate.pl`; não recebe caminho ou comando externo do usuário.
- Revisão de API OpenKore: `src/Plugins.pm` documenta hooks/handles, `src/Commands.pm` confirma a assinatura de registro, `src/Actor/You.pm` expõe `hp_percent`, `sp_percent`, `weight_percent`.

## Limitações que afetam prontidão

- **Não é pronto para uso em personagem real.** A execução continua em shadow por padrão. A configuração explícita `visualBT_enableNativeTasks` habilita somente um perfil `assist` e as cinco tarefas enumeradas acima; ainda faltam testes de integração in-game. `managed` permanece recusado.
- `VisualBT::Snapshot` sanitiza leitores injetados, inclui somente sensores prontos e remove IDs/nome de atores. `OpenKoreReader` e `OpenKoreSensors` conectam leituras nativas e classificações conservadoras de LOS/agressividade/alvo, **ainda não testadas contra jogo real**. Dados incompletos geram `ERROR` em vez de uma falsa declaração de segurança.
- Falta testar integração carregando plugin, três reloads, tarefas reais contra servidor e reconexões. Não foi iniciada sessão de jogo.
- Editor depende de Node/npm; `package-lock.json` foi gerado com sucesso via `npm install --offline` e buildado localmente. Build gerado fica fora do controle de versão; o launcher compila na instalação.
- Alguns itens do capítulo 15 ainda não atendidos: acessibilidade auditada, E2E, simulação igual ao runtime para todos os nós, eventos de runtime alinhados por cursor e validação de 256 KiB no perfil node (há limite HTTP e Perl).

## Próximos passos seguros

1. Reproduzir `npm ci`, build, testes Vitest e Perl em CI (a dependência Perl completa do OpenKore requer provisionamento).
2. Ampliar teste HTTP para rollback, concorrência e tentativas de path traversal com symlinks.
3. Testar reload hooks e a leitura nativa dentro de OpenKore sem habilitar ações.
4. Validar em ambiente controlado a integração das tarefas nativas já cobertas antes de habilitar a configuração manual; implementar separadamente combate, itens, skills, descanso e storage após resolver propriedade/cancelamento.
5. Implementar e testar overlays de memória com restauração condicional antes de considerar `managed`.
