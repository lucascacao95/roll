# Roll

## Identidade do produto

- Nome oficial: **Roll**. Wordmark: **roll.**. Tagline: **From capture to collection.**
- Categoria: utilitário nativo de fotografia para macOS; uma ferramenta digital moderna com alma analógica.
- Público inicial: fotógrafos entusiastas e amadores que usam câmeras dedicadas, preservam seus arquivos e podem fotografar RAW+JPEG.
- Personalidade: simplicidade, cuidado, autonomia, nostalgia, organização e confiabilidade.
- Idioma de desenvolvimento: inglês, com localização em português brasileiro pelo sistema.
- Terminologia: New Roll / Novo rolo, Import Roll / Importar rolo, History / Histórico,
  Previous Rolls / Rolos anteriores, Archive / Acervo, Settings / Ajustes.
- Um roll representa uma sessão de importação. A metáfora não altera pastas, agrupamento, histórico ou regras de cópia.
- Usar SF Pro, componentes nativos, modo claro/escuro, contraste e cores semânticas.
- Paleta de referência: Ivory `#F4EBDD`, Charcoal `#242424`, Amber `#C77736`, Olive `#8C9380`.
  Aplicar a marca em pequenos detalhes, sem fundos bege/texturas generalizados ou decoração que concorra com as fotografias.
- Ícone definitivo pendente: cartucho 35 mm carvão, rótulo âmbar, fundo marfim, tira perfurada,
  sombras sutis e silhueta legível. A primeira imagem de referência foi aprovada como ícone provisório
  e integrada na versão 0.1.1; a arte definitiva continua pendente. Sem logos de fabricantes ou aparência de emoji.
- O produto gerado é `Roll.app`; projeto/target/módulo internos continuam `PhotoImporter`.
  Bundle Identifier, persistência, bookmarks e identificadores existentes devem permanecer compatíveis.
- Diretrizes técnicas e de assets: [docs/BRANDING.md](docs/BRANDING.md).

## Objetivo

Aplicativo nativo para macOS que importa fotografias de cartões SD para uma biblioteca convencional de pastas em SSD externo, com seleção visual, filtros, organização e cópia segura. Não é um editor, catálogo fotográfico ou sistema de backup.  

## Contexto

- Câmera inicial: Panasonic Lumix G100D.

- Arquivos: JPEG (`.JPG`, `.JPEG`) e RAW Panasonic (`.RW2`).

- Mac: SSD interno de 1 TB; biblioteca principal em SSD externo dedicado de 500 GB.

- Uso: organizar fotos em pastas e visualizá-las pelo Finder/Preview.

- Sessões podem conter 350+ fotografias, muitas com pares RAW+JPEG.

  

## Princípios

1. Swift 6 + SwiftUI; APIs nativas primeiro.

2. Biblioteca transparente, sem catálogo proprietário: arquivos acessíveis no Finder.

3. Originais no SD são somente leitura: nunca mover, alterar ou apagar.

4. Sem sobrescrita silenciosa; falhas e interrupções não produzem arquivos finais incompletos.

5. Interfaces simples, operações assíncronas e arquitetura proporcional ao problema.

6. Sem serviços em nuvem, sincronização com Google Fotos/Fotos da Apple ou gerenciamento de backup.

  

## Fluxo principal

1. Conectar cartão SD e SSD externo.

2. Escolher origem (volume ou pasta) e biblioteca de destino.

3. Descobrir arquivos de imagem, inclusive dentro de `DCIM`.

4. Agrupar RAW e JPEG da mesma captura em uma fotografia visual.

5. Filtrar por data da captura, status de importação e formato; selecionar fotografias.

6. Definir nome opcional do evento e pré-visualizar pastas e arquivos de destino.

7. Exibir quantidade de fotografias, quantidade de arquivos, tamanho total e espaço disponível.

8. Copiar diretamente do SD para o SSD externo, verificar a cópia e registrar o resultado.

9. Mostrar resumo de sucesso, falhas ou importação parcial, sem recomendar apagar o SD automaticamente.

  

## Interface

### Importar

- Seletor de origem; detecção de volumes removíveis, com escolha manual de pasta como alternativa.

- Estado da biblioteca: conectada, desconectada, sem permissão, sem espaço.

- Grade de miniaturas com seleção múltipla e carregamento assíncrono.

- Um cartão visual por captura; indicadores `RAW`, `JPEG` ou `RAW + JPEG`.

- Filtros: não importadas, intervalo de datas, formato e opcionalmente busca por nome.

- Destino, organização, nome do evento, prévia e botão Importar.

- Progresso, cancelamento e resumo por arquivo.

  

### Histórico

- Importações com data, origem, destino, contagem de fotografias/arquivos, estado e erros.

- RAW e JPEG registrados individualmente; importações parciais representadas corretamente.

  

### Preferências

- Pasta da biblioteca padrão e reconexão.

- Formato padrão (`RAW`, `JPEG`, ambos).

- Organização por ano/data/evento e subpastas de formato.

- Tratamento padrão de arquivos já importados.

  

## Organização padrão

```text

Fotografias/

2026/

2026-11-21 - Passeio/

RAW/

P1000561.RW2

JPEG/

P1000561.JPG

```

Se não houver evento, usar apenas a data. Preservar nomes originais. Não criar partições nem formatar unidades.

  

## Regras de identificação

- Agrupar por diretório de origem + nome-base, sem confundir nomes iguais em pastas distintas.

- Uma fotografia visual pode representar dois arquivos físicos; filtros de formato determinam quais arquivos serão copiados.

- Priorizar EXIF `DateTimeOriginal`/data de captura; documentar fallback para ausência ou erro de metadados.

- Histórico não é prova suficiente de que o arquivo ainda existe no destino. Revalidar presença e identidade antes de marcar como já importado.

- Evitar falsos positivos em arquivos homônimos; propor estratégia de identidade proporcional (metadados, tamanho, fingerprint/checksum quando necessário).

  

## Requisitos de segurança

- Confirmar que origem e destino não se sobrepõem de maneira perigosa.

- Verificar permissão e espaço antes de importar; reavaliar falhas durante a operação.

- Copiar para arquivo temporário no mesmo volume de destino; validar tamanho e preferencialmente SHA-256; concluir com renomeação segura.

- Nunca substituir arquivo existente silenciosamente; tratar colisões de forma explícita.

- Registrar sucesso somente após a validação; permitir retomar uma importação parcial sem duplicar arquivos íntegros.

- Tratar cancelamento, remoção de unidade, falta de espaço e encerramento inesperado.

- Exibir que importação verificada não equivale a backup independente; não implementar backup no aplicativo.

  

## Implementação técnica

- Swift 6, SwiftUI, Foundation/FileManager e ImageIO/Quick Look quando suportarem os formatos.

- Avaliar suporte real a miniaturas e EXIF de `.RW2` da G100D no macOS disponível; oferecer placeholder/fallback se necessário.

- Monitoramento de volumes com APIs nativas; seleção manual deve sempre funcionar.

- Persistência local simples para histórico e preferências; justificar antes de introduzir SwiftData/SQLite.

- Persistir acesso à pasta escolhida de acordo com sandbox/distribuição, considerando security-scoped bookmarks quando aplicável.

- Separar responsabilidades de descoberta, metadados/miniaturas, agrupamento, planejamento, cópia/verificação e histórico, sem arquitetura excessiva.

- Não exigir ExifTool ou dependências externas no início.

  

## Testes e critérios de aceite

- Testes com diretórios locais simulando SD e SSD, sem hardware obrigatório.

- Descoberta recursiva; agrupamento correto de RAW+JPEG; nomes iguais em diretórios diferentes.

- Filtro de datas e formatos; contagem correta de fotografias versus arquivos.

- Cópia verificada; conflitos; destino ausente; espaço insuficiente; cancelamento e retomada.

- Nenhum arquivo original alterado; nenhum arquivo final incompleto; histórico coerente com o destino.

- Interface responsiva com centenas de fotos.

- Teste manual com arquivos `.RW2` reais antes de assumir compatibilidade de preview.

  

## Entregas incrementais

1. **Descoberta:** projeto compilável; escolha de pasta; varredura; agrupamento e grade de miniaturas.

2. **Importação:** escolha de destino externo; filtros; planejamento; cópia segura e progresso.

3. **Histórico:** persistência, detecção de duplicatas e recuperação de operações parciais.

4. **Polimento:** preferências, reconexão de volumes, mensagens de erro, performance e testes adicionais.

  

## Fora de escopo

- Edição de imagens, revelação RAW, notas, álbuns sociais ou favoritos na nuvem.

- Integração com Google Fotos, Fotos da Apple, iCloud ou outros serviços.

- Backup, sincronização, exclusão automática no SD, formatação de discos.

- Catálogo proprietário, importação para Apple Photos, distribuição comercial e suporte amplo a formatos não testados.

  

## Questões para decidir na implementação

- Versão mínima de macOS e modelo de assinatura/sandbox.

- Estrutura de diretórios e estratégia de conflitos no destino.

- Formato do histórico e identidade de arquivos importados.

- Estratégia de pré-visualização de RW2 quando o sistema não oferecer suporte.
