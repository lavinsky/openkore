# Visual Behavior Tree para OpenKore

Aplicação local para editar e simular árvores de comportamento. O plugin inicia exclusivamente em **shadow**: avalia as condições disponíveis, mostra o ramo previsto e não envia comandos ao personagem. Nenhum modo de ação ou override de configuração está habilitado nesta entrega.

## Requisitos e início

- Perl incluído na instalação OpenKore, com `JSON::PP`.
- Node.js 20 ou superior e npm para compilar/abrir o editor.
- Na raiz deste repositório: `plugins/visualBehaviorTree/bin/start-editor.sh`.
- O launcher instala dependências do editor se necessário, compila a UI e inicia o serviço somente em `127.0.0.1:47851`.
- Copie a URL impressa no terminal para o navegador. O token aparece somente no fragmento `#token=...`, não é enviado ao servidor em requisição de página.

O plugin não é adicionado a `control/sys.txt`. Para testá-lo, carregue-o manualmente pela funcionalidade padrão de plugins do OpenKore. Essa ação não ativa comportamento de jogo: a execução fica em shadow.

## Fluxo de trabalho

1. Abra o editor e ajuste o exemplo Gonryun no canvas. A ordem de `children[]` é prioridade, editável com as setas no inspetor.
2. Salve o rascunho, valide e simule snapshots fictícios.
3. Publique explicitamente. Esta versão aceita publicação apenas em `shadow`; o plugin verifica o grafo de novo antes de trocar a revisão ativa.
4. Acompanhe status/eventos e use `bt status`, `bt pause`, `bt resume`, `bt stop`, `bt reload` ou `bt help` no console.

O exemplo mostra peso `>=48%`, três atacantes observados, descanso com SP baixo, peso abaixo de 50% e ausência de agressivos na área. A caça fica como `Idle`, pois IDs de alvos permitidos dependem do servidor e das regras locais. Embora o catálogo apresente nós de ataque, teleporte, descanso e Kafra, adaptadores reais que não tiveram confirmação de conclusão no OpenKore deste fork não são despachados.

## Dados e segurança

Rascunhos ficam em `control/behaviorTree/graphs`, publicações atômicas em `deployments/current.json`, snapshots em `snapshots`, status sanitizado em `runtime/status.json` e eventos limitados em `runtime/events.ndjson`. Não são lidas/exportadas credenciais de OpenKore. O serviço não oferece execução de shell ou código arbitrário. Ele valida `Host`, token, `Origin` do navegador, JSON e tamanho do corpo; requisições mutáveis não usam GET. Os perfis não devem conter dados privados.

Para desenvolvimento do editor: `cd plugins/visualBehaviorTree/editor`, `npm install`, `npm run serve` com `BT_SESSION_TOKEN` aleatório de pelo menos 40 caracteres e, em outro terminal, `npm run dev`. Abra o endereço Vite com o mesmo fragmento `#token=...` impresso pelo serviço; o proxy de desenvolvimento encaminha a API local. Para produção use o launcher.

## Limitações conhecidas

- O snapshot conectado ainda coleta somente HP/SP/peso/mapa quando disponibilizados pelo objeto do personagem. Dados de posição, inventário, LOS, agressividade e tarefas retornam erro se ausentes.
- Ações de jogo, modos `assist`/`managed`, overlays e cancelamento de tasks estão bloqueados até integração/testes contra este commit; nenhum valor de configuração é alterado.
- Ainda não há importador de config, seleção de alvo, comparador de conflitos ou validação em jogo. O painel de eventos é polling local.

Consulte `docs/BT_IMPLEMENTATION_STATUS.md` para a matriz de fases e evidência de testes.
