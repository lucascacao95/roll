# Roll

**roll.** — *From capture to collection.*

Utilitário nativo de macOS para importar fotografias de cartões SD e pastas para um acervo convencional.
Inglês como idioma de desenvolvimento e suporte a português brasileiro. Diretrizes de marca, compatibilidade
e direção do ícone definitivo estão em [docs/BRANDING.md](docs/BRANDING.md).
O escopo do produto está em [PROJECT_SCOPE.md](PROJECT_SCOPE.md).

## Estado atual: identidade Roll e localização

A versão 0.1.1 inclui o ícone provisório aprovado: a primeira imagem do cartucho de filme,
com todos os tamanhos nativos em `PhotoImporter/Assets.xcassets/AppIcon.appiconset`.
Finder, Dock e Sobre usam o mesmo ícone. A arte definitiva continua pendente.

- Escolha manual de uma pasta ou cartão pelo seletor nativo; lista de volumes externos detectados.
- Preferências persistentes de formato, filtro de importadas e organização de pastas.
- Biblioteca padrão salva com bookmark de acesso e verificação de identidade ao reconectar.
- Descoberta recursiva de JPG, JPEG e RW2, inclusive em DCIM.
- Um cartão visual por diretório relativo + nome-base, com indicação RAW/JPEG.
- Nomes-base preservam maiúsculas/minúsculas. Extensões são reconhecidas sem distinguir caixa.
- JPG e JPEG do mesmo nome-base são mantidos; nenhum arquivo é descartado pelo agrupamento.
- Miniaturas assíncronas, respeitando orientação, com decodificação serial e cache limitado.
- Preview tenta todos os JPEGs do grupo antes de tentar RAW via ImageIO; falhas usam placeholder.
- Leitura de datas por arquivo; uma data representativa por fotografia visual, com origem identificada.
- Seleção por cartão, ações para selecionar visíveis/limpar e contagem de fotografias, arquivos e bytes.
- Filtros combinados de formato e intervalo inclusivo de dias.
- Erros de leitura são exibidos como resultado parcial.
- Cancelamento e troca de origem; arquivos ocultos, pacotes e links simbólicos são ignorados.
- Escolha da pasta da biblioteca, nome opcional do evento e prévia por arquivo.
- Verificação de caminhos, arquivos existentes, conflitos, disponibilidade e espaço livre.
- A prévia permanece somente leitura. O botão Importar habilita cópia verificada para a biblioteca.
- Cópia em blocos, temporários exclusivos no destino, SHA-256, finalização sem sobrescrita e progresso.
- Cancelamento, resumo individual de RAW/JPEG e nova tentativa verificando conteúdo já existente.
- Registro local JSON por operação, com estado, identidade das raízes/volumes e resultado por arquivo.
- Histórico visual com resultado registrado e conferência atual do destino por tamanho/SHA-256.
- Preparação de retomada após confirmar origem e biblioteca, preservando caminhos e cópias íntegras.
- Inspeção e remoção confirmada de temporários com identidade registrada, protegendo operações ativas.
- Filtro de arquivos não importados nesta biblioteca, incluindo pares parcialmente importados.

## Datas, filtros e seleção

A prioridade de data é aplicada ao grupo inteiro: EXIF `DateTimeOriginal`, EXIF `DateTimeDigitized`,
criação do arquivo e modificação do arquivo. Dentro da mesma prioridade, preferir JPEG;
entre arquivos do mesmo formato, usar a ordem do caminho relativo. Isso permite, por exemplo,
usar EXIF do RAW antes da criação do JPEG. Datas inválidas são ignoradas e os fallbacks
são identificados no cartão. O detalhe ao passar o cursor mostra horário, origem e arquivo usado.

O dia e horário EXIF são preservados como valores civis da câmera, sem conversão de fuso,
inclusive quando há offset EXIF. Datas do filesystem usam o fuso local do Mac no momento
da descoberta. O intervalo de filtro compara dias gregorianos e inclui os dias inicial e final.
Fotografias sem data válida aparecem sem filtro de data e ficam ocultas quando ele está ativo.
O intervalo inicial abrange todas as datas disponíveis da descoberta.

Formato define os arquivos elegíveis, sem separar o cartão do par: 10 pares selecionados
representam 10 fotografias/20 arquivos em Todos e 10 fotografias/10 arquivos em JPEG ou RAW.
Se um grupo contiver JPG e JPEG, ambos continuam elegíveis no formato JPEG.
Os indicadores RAW/JPEG do cartão mostram os formatos existentes, independentemente do filtro.

A seleção começa vazia. Mudar filtros desmarca fotografias que deixaram de estar visíveis;
ampliar filtros não as seleciona novamente. Trocar de origem limpa seleção e filtros.
Não há seleção oculta. Todas as contagens e tamanhos consideram os arquivos elegíveis.

### Não importadas nesta biblioteca

Depois de escolher a biblioteca, ative **Não importadas nesta biblioteca**. O aplicativo lê os registros
locais, calcula o SHA-256 da origem quando há referências candidatas e confere o conteúdo existente
no destino. Só arquivos cuja origem e destino correspondam são ocultados. Nome, tamanho ou registro
de sucesso isolados não bastam. Erros, arquivos sem referência, registros corrompidos e arquivos ausentes
ou alterados permanecem visíveis; observações da verificação ficam disponíveis abaixo do filtro.
Não há varredura/catalogação de toda a biblioteca: a consulta utiliza caminhos registrados.

O filtro age por arquivo físico. Se o JPEG de um par estiver íntegro e o RAW ainda faltar, o cartão
continua visível com apenas o RAW elegível em Todos/RAW; em JPEG ele fica oculto. Contagens, tamanhos
e planejamento consideram somente arquivos elegíveis. A data representativa original do par é mantida
mesmo quando o JPEG é excluído da seleção pelo filtro.

A verificação é refeita ao ativar o filtro e antes de gerar a prévia. Após alterações externas,
use **Atualizar verificação**. Até terminar a conferência, arquivos não verificados ficam visíveis.
O horário mostrado identifica o instante da verificação; mudanças externas ainda não são monitoradas.

## Biblioteca e prévia da importação

Escolha uma pasta existente usando **Escolher biblioteca…**. Essa pasta é a raiz da biblioteca;
não será acrescentado outro nível `Fotografias`. Pastas locais são permitidas para testes,
e a prévia identifica se o volume é interno ou externo quando essa informação estiver disponível.
O seletor da biblioteca não permite criar pastas nesta etapa.

Com fotografias selecionadas, informe opcionalmente o evento e clique em **Gerar prévia**.
A janela mostra origem relativa, destino relativo à biblioteca, formato, tamanho e estado de cada arquivo.
Exemplo para uma biblioteca já chamada `Fotografias`:

```text
Fotografias/2026/2026-11-21 - Passeio/RAW/P100001.RW2
Fotografias/2026/2026-11-21 - Passeio/JPEG/P100001.JPG
```

Sem evento, a pasta da sessão é somente a data. Uma seleção com vários dias gera uma pasta por dia.
O par utiliza a mesma data representativa, mesmo quando apenas RAW ou JPEG está elegível.
Fotografias sem data válida ficam com pendência, sem destino inventado; desmarque-as para continuar.

Os nomes originais são preservados. O evento tem espaços externos aparados, e nomes perigosos ou
incompatíveis são rejeitados, sem substituir caracteres automaticamente. É aplicada uma política
conservadora para separadores, caracteres de controle, ponto/espaço final e limites de comprimento
(255 bytes UTF-8 por componente; evento de até 242 bytes para caber junto da data).

Estados por arquivo:

- **Novo:** caminho livre no momento da inspeção.
- **Existe — verificar:** arquivo no destino; nome e tamanho não comprovam duplicidade.
- **Pendência:** colisão entre selecionados, link simbólico, caminho inacessível/incompatível,
  data ausente ou origem removida/alterada em tamanho desde a descoberta.

O planejamento rejeita origem e biblioteca iguais ou contidas uma na outra, resolvendo links nos
ancestrais e comparando componentes de caminho. A comparação de sobreposição é conservadora para
maiúsculas/minúsculas. Links na própria raiz selecionada ou em componentes existentes do destino
são bloqueados, inclusive links quebrados. Arquivos ocupando o lugar de pastas também são bloqueados.
Nomes de destino são comparados com normalização Unicode e as regras de caixa do volume;
se a sensibilidade não puder ser obtida, assumir comparação sem distinção de caixa.

O tamanho previsto inclui todos os arquivos elegíveis, inclusive existentes, até verificar seu conteúdo.
Espaço desconhecido/insuficiente e volume somente leitura são indicados na prévia. A permissão
efetiva de gravação não é testada durante a prévia.
A prévia não cria arquivo/pasta de teste, não reserva espaço nem altera metadados no destino.

Alterar seleção, filtros, evento, origem ou biblioteca descarta a prévia e cancela seu cálculo em andamento.
Eventos de montagem, desmontagem e renomeação de volumes descartam descobertas e prévias antigas;
escolha a origem novamente. Alterações de arquivos dentro de um volume não são monitoradas. Ao importar, caminhos, permissões, identidades e espaço são revalidados.
O planejamento não calcula checksums nem declara arquivos como já importados.

## Importação e nova tentativa

Na prévia sem pendências, clique em **Importar**. A seleção e os controles ficam bloqueados durante
a operação; é possível cancelar e acompanhar o arquivo atual e as etapas de cópia/verificação.
O serviço de importação é serial e compartilhado entre as janelas do aplicativo.

Antes de copiar, revalidar identidade das pastas (dispositivo/inode), UUID dos volumes quando disponível,
presença/tamanho/identidade e datas de alteração dos arquivos de origem, sobreposição e capacidade atual.
Mudanças desde a prévia exigem nova descoberta/prévia. A criação real do temporário verifica o acesso
de escrita; falhas de permissão, desconexão ou espaço são registradas. O espaço também é reconsultado
por arquivo. Na nova tentativa, arquivos agora existentes são excluídos da estimativa de espaço de cópia,
mas continuam sujeitos à comparação de conteúdo.

O percurso de pastas e os arquivos são abertos por descritores com `O_NOFOLLOW`; a origem usa somente
aberturas de leitura. No destino, criar temporário oculto exclusivo no mesmo diretório do arquivo final.
Copiar com buffer de 1 MiB, calculando SHA-256 da origem; sincronizar a escrita e reler o temporário
inteiro para comparar tamanho e SHA-256. Revalidar origem e caminhos antes de publicar o arquivo com
`renameatx_np(RENAME_EXCL)`, que recusa substituir um nome existente. Não há fallback para renomeação
que possa sobrescrever. Se o filesystem não suportar essa finalização, a operação falha explicitamente.
A sincronização do diretório é exigida antes de registrar o arquivo como copiado.

Arquivos existentes são abertos sem seguir links. Comparar tamanho e SHA-256 completo da origem e
do destino, conferindo que permaneceram inalterados durante a leitura. Conteúdo igual é registrado
como **Já presente — conteúdo verificado**; conteúdo diferente é conflito, sem alteração do existente.
Falhas por arquivo permitem representar pares parcialmente importados. Falhas graves de I/O, espaço
ou registro interrompem a operação; o resumo diferencia falhas, cancelados e arquivos não iniciados.

**Verificar e tentar novamente** repete a operação sobre a prévia, revalidando os arquivos existentes.
Depois de mudar origem, seleção ou organização, gere outra prévia. Arquivos finais íntegros não são
recopiados quando seu conteúdo corresponde à origem. RAW é copiado como bytes: não é necessário que
seu preview seja suportado. Datas EXIF são preservadas; datas, permissões e atributos adicionais do
filesystem da origem não são replicados para o destino.

### Registros de importação

Os registros ficam no Application Support do container do aplicativo, em `PhotoImporter/Imports`,
um JSON versionado por operação. São gravados atomicamente e sincronizados antes de escrever na
biblioteca, após validar o temporário e após publicar cada arquivo. Cada registro contém caminhos,
tamanhos, nomes dos temporários, SHA-256 quando disponível, estados e erros. O identificador aparece
no resumo da operação. Não existe catálogo proprietário na biblioteca. Registros novos usam versão 2,
incluindo estado da origem, identidade do temporário e vínculo com a operação retomada. A leitura aceita
versões 1 e 2, sem reescrever silenciosamente registros antigos. Arquivos `.lock` locais protegem operações
ativas entre janelas/instâncias; as travas são liberadas pelo sistema quando o processo termina.

Uma falha de registro antes da cópia impede a operação. Uma falha depois da publicação pode deixar
um arquivo final íntegro com estado ainda pendente/erro: a nova tentativa confere o conteúdo real,
sem confiar somente no registro.

No cancelamento e nas falhas tratadas, tentar remover apenas o temporário criado pela própria operação.
Encerramento abrupto ou desconexão podem deixar temporários ocultos `.photoimporter-<operação>-<índice>.partial`,
identificados no registro, sem apresentá-los como arquivos finais completos. O histórico identifica
operações novas interrompidas quando o registro está em andamento e a trava não está mais ativa.
Não houve teste de perda física de energia. A sincronização não equivale a garantia absoluta de
durabilidade do dispositivo nem a backup independente. Os originais nunca são removidos do cartão.

## Histórico, conferência e retomada

Abra **Histórico** no cabeçalho. Cada operação mostra data, origem, destino, contagem de fotografias/
arquivos e resultado individual de RAW/JPEG. Registros corrompidos ou de versão desconhecida são
reportados sem ocultar os demais nem alterar seus arquivos JSON.

Selecione uma operação e use **Confirmar biblioteca…** para conceder acesso à pasta atual. UUID do
volume e identidade da pasta são conferidos; outra unidade/pasta não é aceita só por ter o mesmo nome.
Quando há UUID estável, uma mudança de identificador do dispositivo após remontagem não impede o
reconhecimento da mesma pasta/inode. Sem identidade suficiente, ações de escrita são bloqueadas.

**Conferir destino** apenas lê os arquivos, sem exigir o cartão conectado. A coluna **Resultado
registrado** preserva o que aconteceu na operação; **Destino agora** mostra conteúdo íntegro, ausente,
diferente, sem checksum de referência ou indisponível. Uma cópia pode ser confirmada mesmo quando
o processo terminou após publicá-la e antes de registrar sucesso. O horário de conferência é exibido;
atualize após mudanças externas. O aplicativo não transforma presença em comprovação sem SHA-256.

Para retomar:

1. Confirmar a origem e a biblioteca usando os seletores nativos.
2. Clicar em **Preparar retomada**. Os caminhos originais de destino são preservados e arquivos
   já íntegros são excluídos da nova cópia. A origem dos demais é conferida contra o estado/checksum
   registrado. Origem alterada, conflito de conteúdo e falta de espaço aparecem como pendências.
3. Clicar em **Abrir prévia da retomada**, revisar os arquivos e então **Importar**.

A retomada gera uma nova operação vinculada à anterior. O resultado original não é sobrescrito.
O histórico oferece navegação entre as tentativas e pode usar checksums de retomadas vinculadas
quando identidades, origem e destinos correspondem, sempre relendo o destino atual. Cadeias cíclicas
ou excessivamente profundas são tratadas conservadoramente, sem inferir conteúdo.

Registros antigos sem estado/checksum da origem não autorizam retomada automática de arquivos pendentes:
faça uma nova descoberta. Registros versão 1 em andamento, sem trava, têm atividade desconhecida;
suas ações de recuperação/limpeza são bloqueadas, pois podem pertencer a uma instância antiga ainda ativa.
Não há cópia automática ao iniciar o aplicativo ou abrir o histórico.

### Temporários registrados

Com a biblioteca confirmada, clicar em **Verificar temporários**. A lista mostra somente os nomes
exatos previstos pelo registro. **Remover temporários verificados…** pede confirmação da limpeza e
revalida as identidades antes de remover. Somente arquivos regulares com identidade registrada,
tamanho compatível, mesma data de criação registrada e sem outros hard links são elegíveis. Se a data
de criação não estiver disponível, o temporário é preservado. Isso evita confiar apenas em um inode
que possa ter sido reutilizado pelo filesystem. Links simbólicos, nomes estranhos, arquivos
substituídos após a inspeção e temporários antigos sem identidade permanecem intactos. Arquivos finais
e originais não são alvos da limpeza. Operações ativas ficam protegidas pela trava.

Se a inspeção/limpeza for cancelada ou uma unidade ficar indisponível, conferir novamente o destino.
A biblioteca padrão possui acesso persistente. As confirmações de origem e biblioteca no histórico
continuam explícitas, por operação, antes de ações de recuperação ou limpeza.

## Interface e navegação

A janela usa barra lateral com **New Roll / Novo rolo**, **History / Histórico** e **Settings / Ajustes**, inspirada nos mockups
fornecidos. A tela Importar apresenta origem e destino em cartões, formato/organização e evento,
grade de seleção com filtros e resumo fixo de fotografias, arquivos e tamanho. O conteúdo é rolável;
a grade continua com carregamento preguiçoso de miniaturas. **Review Roll / Revisar rolo** abre a prévia existente:
a cópia exige confirmar **Importar** nessa prévia. Erros e cancelamento da prévia ficam junto da ação principal.

Histórico apresenta cartões com data, sessão extraída do caminho registrado, contagens, origem,
destino e estado real. Há filtros de período e estado. Ao abrir um cartão, os detalhes preservam
conferência de conteúdo, confirmação de pastas, retomadas vinculadas e limpeza confirmada de temporários.
Os cartões usam ícones: não há leitura automática de fotos sem autorização para ilustrar registros.
A transição da retomada fecha os detalhes antes de abrir a prévia na tela Importar.

Preferências usa seções de biblioteca, organização, formato, arquivos já importados e segurança.
A data permanece obrigatória, o evento é definido por importação, não existe opção de sobrescrita e
SHA-256 continua obrigatório. Os números de capacidade vêm do volume escolhido, sem valores fixos
dos mockups; o rodapé identifica que a consulta foi feita na conexão. A cópia revalida espaço e acesso.
A marca usa wordmark `roll.`, destaque âmbar e fundos semânticos nativos. Sobre Roll e Ajustes
estão disponíveis no menu do aplicativo. A janela inicia em 1280 × 880 e permite redimensionar a partir de 1040 × 740.

O usuário informou ter validado o fluxo manual anterior com cartão, SSD e RW2 reais, incluindo
reabertura/reconexão e uma sessão grande. Essa confirmação se refere ao fluxo antes da reorganização
visual; a navegação e os controles novos precisam ser conferidos no aplicativo atualizado.

## Preferências e volumes

Abra **Preferências…** (⌘,) para escolher a biblioteca padrão, formato inicial (ambos/RAW/JPEG),
filtro inicial de não importadas e presença das pastas de ano e de formato. A pasta de data e evento
opcional e os nomes originais são sempre preservados. Os padrões iniciais mantêm o layout anterior.
Formato e filtro valem para novas descobertas; **Aplicar padrões aos filtros atuais** atualiza a sessão.
Organização vale para novas prévias; mudanças exigem recalcular a prévia. Retomadas mantêm os caminhos registrados.
Arquivos existentes continuam sujeitos à comparação de conteúdo, sem opção de sobrescrita silenciosa.

Preferências usam UserDefaults no container local do aplicativo. A biblioteca é lembrada por um
security-scoped bookmark, com entitlement de bookmark no escopo do app. Ao abrir ou reconectar,
resolver sem montar unidades ou mostrar diálogos automáticos; conferir UUID do volume, inode e data
de criação da pasta (quando disponíveis). Sem UUID, exigir também o mesmo dispositivo.
Um caminho salvo serve apenas para exibição, nunca para conceder acesso ou escolher outra pasta.
Bookmarks desatualizados são renovados somente após validar a identidade. Se estiverem inválidos,
sem permissão ou se a identidade divergir, escolher a pasta novamente. Mudanças de nome/localização
podem exigir essa confirmação se o resolvedor nativo não encontrar a pasta original.
**Esquecer pasta** remove somente a preferência; nenhum arquivo da biblioteca é apagado.

O menu **Volumes** lista unidades externas/removíveis/ejetáveis visíveis ao sandbox. Escolher uma
abre o seletor nativo nessa unidade para autorizar a origem. A seleção manual continua disponível.
NSWorkspace monitora montagem, desmontagem e renomeação: a biblioteca tenta reconectar e a descoberta/
prévia anterior é descartada, exigindo nova escolha da origem. Nenhum evento inicia uma cópia.
Durante uma importação, o motor mantém seu próprio acesso e suas verificações; a atualização de acesso
é adiada até terminar, preservando o resumo. Retirada física continua sujeita à validação manual.
Acesso de leitura/escrita e disponibilidade são mostrados na biblioteca; capacidade e espaço necessário
são conferidos na prévia e novamente durante a cópia. Não há arquivo de teste de escrita na reconexão.

## Requisitos e execução

macOS 27+, Xcode 27+ e Swift 6. Sem dependências externas, conta Apple ou provisioning profile.
O projeto usa assinatura local ad hoc e App Sandbox com acesso de leitura/escrita às pastas escolhidas,
necessário para o destino. O código de origem continua usando somente leitura e não cria, altera,
move ou remove arquivos do cartão. A gravação dos registros locais é rejeitada se sua pasta se
sobrepuser à origem ou à biblioteca.
O `PrivacyInfo.xcprivacy` declara as consultas locais de capacidade e metadados de arquivos,
conforme as [categorias e motivos documentados pela Apple](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

Abra `PhotoImporter.xcodeproj`, selecione o scheme compartilhado **PhotoImporter** e execute no Mac.
Alternativamente, na raiz do repositório:

```sh
xcodebuild -project PhotoImporter.xcodeproj \
  -scheme PhotoImporter -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/PhotoImporterDerivedData \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- test -testLanguage pt-BR -testRegion BR

xcodebuild -project PhotoImporter.xcodeproj \
  -scheme PhotoImporter -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/PhotoImporterDerivedData \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- build

open /tmp/PhotoImporterDerivedData/Build/Products/Debug/Roll.app
```

O build normal após os testes restaura os entitlements normais: o Xcode acrescenta exceções
temporárias de acesso ao hospedar testes no aplicativo. Essas exceções não fazem parte do arquivo
de entitlements do projeto.

## Instalador local (DMG)

Para gerar uma versão Release para este Mac:

```sh
./scripts/package-local.sh
```

O projeto/target/scheme e módulo continuam `PhotoImporter`; o produto/executável são `Roll`.
O Bundle Identifier e `PhotoImporter/Imports` permanecem inalterados, sem migração de dados.
Não use simultaneamente a cópia antiga `PhotoImporter.app` e `Roll.app`, que compartilham a mesma identidade.

O script compila para Apple Silicon (`arm64`), verifica a assinatura ad hoc e cria
`build/releases/Roll-0.1.1-macOS-arm64.dmg`, acompanhado do SHA-256 e do log de build.
O diretório `build/` já é ignorado. Uma imagem existente não é sobrescrita: preserve ou renomeie
o DMG anterior antes de repetir o empacotamento. Não exige conta Apple nem envia arquivos à Apple.

Sem importações em andamento, encerre o app aberto. Abra o DMG, arraste `Roll.app`
para **Applications (Aplicativos)**, ejete a imagem e abra o aplicativo instalado.
Requer macOS 27+ e Apple Silicon. A biblioteca pode precisar ser autorizada novamente.

Essa imagem serve para instalação local. A assinatura ad hoc não equivale a Developer ID ou
notarização; distribuir para outras pessoas pode gerar bloqueios do Gatekeeper. Uma distribuição
notarizada exige credenciais e certificado próprios do Apple Developer Program e um processo
separado de assinatura/notarização. O script não altera as configurações de segurança do Mac.

## Validação

Os 94 testes criam e removem apenas suas próprias pastas temporárias. Não requerem cartão ou SSD.
Cobrem recursão, formatos, pares e nomes repetidos entre diretórios, JPG+JPEG simultâneos,
distinção de caixa nos nomes-base, arquivos ocultos e links, pastas vazias e origens inválidas,
erros de permissão, cancelamento, troca de origem e 360 pares/720 arquivos.
JPEGs gerados com EXIF controlado validam leitura de datas, prioridade e fallback, offsets sem
deslocamento do dia, orientação, decodificação e tamanho de miniatura. Também são testados
limites inclusivos de datas, filtros combinados, seleção, contagens/tamanhos por formato,
remoção de seleções ocultadas e reset ao trocar de origem.
Conteúdo, criação e modificação dos arquivos de origem são comparados antes/depois da leitura.
Arquivos RW2 fictícios validam reconhecimento por extensão e agrupamento, não o formato RAW.
Os testes de planejamento usam diretórios reais simulando SD e biblioteca. Cobrem organização com/sem
evento, vários dias, formatos, arquivos existentes, colisões de nomes e Unicode, sobreposição,
links quebrados/escapando do destino, falta de acesso, destino ausente, origem removida/alterada,
cancelamento e invalidação da prévia. Capacidade insuficiente/desconhecida, regras de caixa e volume
somente leitura são simulados por uma consulta de volume injetável; os demais acessos são reais.
Snapshots de conteúdo e datas de arquivos/pastas confirmam que a prévia não altera origem nem biblioteca.
Os testes de importação fazem cópias reais entre diretórios, conferindo bytes e SHA-256, arquivos de
origem somente leitura, registro JSON e nova tentativa sem recópia. Cobrem conflito de mesmo tamanho,
par parcial, corrupção do temporário, cancelamento durante cópia e antes da publicação, arquivo
concorrente no instante do rename, alteração da origem, troca de pasta por symlink, biblioteca
substituída, UUID de volume divergente, espaço insuficiente, falha de escrita e falha do registro.
Os checkpoints simulam falhas sobre arquivos reais; ENOSPC/desconexão não foram provocados em hardware.
Um erro simulado após publicação confirma que a nova tentativa verifica o arquivo final íntegro.
Os testes de histórico constroem interrupções com registros em andamento e temporários parciais em disco.
Cobrem versões antigas, JSON corrompido, trava ativa, destino ausente/alterado, retomadas parciais e em várias
tentativas, origem alterada, pastas erradas, paths adulterados, cancelamento da limpeza e preservação de
temporários desconhecidos, substituídos, simbólicos, ligados por hard link ou com identificador reutilizado.
O filtro é validado por arquivo,
incluindo contagens e data de par parcial, homônimos com conteúdos distintos e reimportação após perda do destino.
Os testes de preferências usam domínios isolados de UserDefaults. Cobrem persistência, valores inválidos,
padrões na descoberta, bookmarks nativos entre instâncias de acesso, pasta ausente, identidade divergente,
pasta substituída no caminho antigo, links, notificação de montagem e descarte da prévia/seleção.
As quatro combinações de organização e colisões são verificadas; uma cópia real confirma o layout
alternativo e a preservação do original. Mudança de organização exige nova prévia antes de copiar.
Não foi feito encerramento forçado de processo nem teste físico de desconexão/perda de energia.

Verificação manual no aplicativo:

1. Escolher uma pasta com arquivos JPG/RW2, inclusive em subpastas DCIM.
2. Conferir agrupamento, miniaturas, datas, indicadores e contagem de fotografias versus arquivos.
3. Selecionar pares, alternar Todos/JPEG/RAW e conferir arquivos e tamanho elegíveis.
4. Ativar o intervalo de datas, conferir seus limites e as seleções removidas ao estreitar o filtro.
5. Escolher outra origem, cancelar uma varredura e testar uma pasta vazia.
6. Selecionar um cartão real e conferir leitura sob sandbox sem alterar os originais.
7. Usar RW2 reais da G100D, isolados e em pares, e conferir EXIF e preview RAW.
8. Escolher a biblioteca, informar um evento e gerar a prévia. Conferir caminhos, volume, espaço e contagens.
9. Fechar a prévia, mudar seleção/formato/evento e gerar outra; conferir atualização dos destinos e arquivos.
10. Testar uma biblioteca com arquivos existentes e conferir que eles aparecem como pendentes de verificação,
    sem sobrescrita ou criação de pastas/arquivos.
11. Usar primeiro diretórios de teste, clicar em Importar e conferir destinos, SHA-256 e resumo no Finder.
12. Repetir a importação e conferir o estado de conteúdo já presente, sem recópia.
13. Cancelar uma seleção maior e conferir que nenhum arquivo final ficou incompleto; gerar nova tentativa.
14. Abrir Histórico, confirmar a biblioteca e conferir **Resultado registrado** versus **Destino agora**.
15. Em diretórios de teste, remover/alterar uma cópia e repetir a conferência; o original deve permanecer intacto.
16. Preparar a retomada de uma operação incompleta, confirmar as duas pastas e revisar a prévia antes de importar.
17. Inspecionar os temporários registrados, conferir os caminhos da lista e confirmar somente a limpeza elegível.
18. Ativar **Não importadas nesta biblioteca**, testar um par parcialmente importado e conferir os arquivos elegíveis.
19. Alterar preferências, reabrir o app e conferir formato, filtro, organização e biblioteca lembrados sob sandbox normal.
20. Com unidades de teste, retirar/reconectar o SSD e verificar estado e restauração da biblioteca; escolher a origem novamente.
21. Conectar outra unidade com o mesmo nome: ela não pode substituir a biblioteca original automaticamente.
22. Conferir o menu Volumes e o seletor manual com cartão e SSD reais; testar perda de permissão e nova autorização.

Os testes de branding conferem o produto Roll com Bundle Identifier/caminho de histórico preservados,
leitura dos valores antigos de formato e catálogos inglês/pt-BR com placeholders correspondentes.
Os testes tradicionais rodam em pt-BR para preservar asserções de mensagens; a localização testa os dois idiomas.
O build e os testes automatizados foram executados localmente. O usuário confirmou o fluxo manual
anterior com cartão e SSD reais. As três telas novas foram renderizadas nativamente com diretórios
simulados em 1280 × 880 e 1040 × 740, incluindo uma importação real de seis JPEGs de teste.
Essas renderizações verificam layout, sem substituir a interação manual: a automação de interface
não tem permissão de Acessibilidade neste ambiente. Conferir navegação, seletores, filtros e retomada
na interface reorganizada.

## Limitações e próximo passo

O usuário confirmou a validação manual de RW2 reais, reabertura/reconexão e sessão grande no fluxo anterior.
Retirada física durante cópia e perda de energia não foram validadas.
Bookmarks foram testados com diretórios temporários e múltiplas instâncias do serviço de acesso.
Permissões revogadas e o fluxo visual reorganizado ainda precisam de teste manual.

O próximo passo é conferir a nova navegação, a seleção/rolagem, os filtros do histórico e a abertura
de detalhes e retomada no app; depois preparar uma versão Release local para uso cotidiano.
