# Visual Behavior Tree para OpenKore

Aplicação local para editar e simular árvores de comportamento. O editor só publica perfis em **shadow** por padrão: avalia as condições disponíveis, mostra o ramo previsto e não envia comandos ao personagem. Existe um adaptador nativo experimental, não ativado nem validado em jogo; não use em personagem real antes dos testes de integração. Não há overrides de configuração ativos.

## Requisitos e início

- Perl incluído na instalação OpenKore, com `JSON::PP`.
- Node.js 20 ou superior e npm para compilar/abrir o editor.
- Na raiz deste repositório: `plugins/visualBehaviorTree/bin/start-editor.sh`.
- O launcher instala dependências do editor se necessário, compila a UI e inicia o serviço somente em `127.0.0.1:47851`.
- Abra a URL local impressa no terminal. O launcher imprime uma URL com token no fragmento `#token=...`; ele não é enviado nas URLs HTTP. A interface usa o token somente na sessão do navegador. Não compartilhe essa URL.

O plugin não é adicionado a `control/sys.txt`. Para testá-lo, carregue-o manualmente pela funcionalidade padrão de plugins do OpenKore. Essa ação não ativa comportamento de jogo: a execução fica em shadow.

## Fluxo de trabalho

1. Crie um perfil ou abra um perfil salvo. A ordem de `children[]` define prioridade e pode ser alterada no inspetor; arraste nós da paleta para o canvas e conecte-os.
2. Edite o cenário fictício, salve o rascunho, valide e simule. Salvar usa criação para perfis novos e ETag para atualizações concorrentes.
3. Publique explicitamente. Esta versão aceita publicação apenas em `shadow`; o plugin verifica o grafo de novo antes de trocar a revisão ativa.
4. Acompanhe heartbeat/eventos e revisão reconhecida. Pause/resume ainda não é oferecido pela interface porque não há endpoint seguro para isso.

O exemplo mostra peso `>=48%`, três atacantes observados, descanso com SP baixo, peso abaixo de 50% e ausência de agressivos na área. A caça é ilustrada com `AttackTarget`, que não despacha nenhuma ação em shadow. O catálogo inclui ataque, teleporte, descanso e Kafra, mas os adaptadores sem confirmação integrada no OpenKore são recusados no modo assist.

## Dados e segurança

Rascunhos ficam em `control/behaviorTree/graphs`, publicações atômicas em `deployments/current.json`, snapshots em `snapshots`, status sanitizado em `runtime/status.json` e eventos limitados em `runtime/events.ndjson`. Não são lidas/exportadas credenciais de OpenKore. O serviço não oferece execução de shell ou código arbitrário. Ele valida `Host`, token, `Origin` do navegador, JSON, tamanho do corpo e diretórios resolvidos sem symlinks; requisições mutáveis não usam GET. O token aparece somente na URL inicial impressa no terminal do launcher, não nos logs de requisição HTTP. Os perfis não devem conter dados privados.

Para desenvolvimento do editor: `cd plugins/visualBehaviorTree/editor`, `npm install`, `npm run serve` com `BT_SESSION_TOKEN` aleatório de pelo menos 40 caracteres e, em outro terminal, `npm run dev`. Abra o endereço Vite com o mesmo fragmento `#token=...` impresso pelo serviço; o proxy de desenvolvimento encaminha a API local. Para produção use o launcher.

## Limitações conhecidas

- O snapshot conectado lê HP/SP/peso/mapa, posição, inventário, status e monstros, quando os objetos do OpenKore estão prontos. LOS, agressividade e atacantes são observações conservadoras que falham fechadas quando faltam dados. Ainda não foram verificadas em jogo.
- A interface publica apenas `shadow`. O módulo experimental de tarefas suporta sentar/levantar, movimento no mapa atual e teleporte com conclusão/identidade testadas em mocks; a execução `assist` exige configuração manual explícita e NÃO está validada em jogo. `managed`, Kafra, combate, itens, skills e overrides não estão implementados.
- Ainda não há importador de config, seleção de alvo, comparador de conflitos ou validação em jogo. O painel de eventos é polling local.

Consulte `docs/BT_IMPLEMENTATION_STATUS.md` para a matriz de fases e evidência de testes.
