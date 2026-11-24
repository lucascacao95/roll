# Roll — identidade e implementação

- Nome oficial e produto gerado: **Roll** (`Roll.app`, executável `Roll`).
- Wordmark: **roll.**, fonte do sistema, semibold; tagline fixa **From capture to collection.**
- Utilitário nativo de fotografia para macOS; ferramenta digital moderna com alma analógica.
- Público: entusiastas e amadores com câmeras dedicadas, arquivos próprios e pares RAW+JPEG.
- Simplicidade, cuidado, autonomia, nostalgia, organização e confiabilidade.

## Uso visual

SF Pro e componentes SwiftUI nativos. Wordmark compacto na barra lateral e Sobre; fotografias
continuam protagonistas. Ivory `#F4EBDD`, Charcoal `#242424`, Amber `#C77736`, Olive `#8C9380`.
A paleta está em `PhotoImporter/Assets.xcassets`. Fundos permanecem semânticos do macOS, sem
texturas ou preenchimento bege generalizado. Amber marca o wordmark e a seção selecionada,
com texto Charcoal. Olive aparece na capacidade de armazenamento, não como substituto de sucesso.
O AccentColor usa variantes acessíveis: `#985322` no modo claro e `#DEA36F` no escuro.
Sucesso, erro, alerta e informação mantêm cores semânticas. Sem fontes ou dependências externas.

## Linguagem

Idioma de desenvolvimento e fallback: inglês. `Localizable.xcstrings` contém inglês e pt-BR,
incluindo mensagens de erro, verificação e recuperação. O macOS escolhe pelo idioma preferido;
não há seletor próprio que sobrescreva o sistema. O app usa New Roll / Novo rolo, History /
Histórico, Previous Rolls / Rolos anteriores, Archive / Acervo, Settings / Ajustes e Import Roll /
Importar rolo. Mensagens técnicas permanecem explícitas. Textos já gravados em registros antigos
permanecem no idioma original, sem reescrever o histórico.

`Localization.swift` formata argumentos separados do texto traduzido. Placeholders `%@` devem
preservar quantidade e ordem entre idiomas; nomes e caminhos não são traduzidos. Novas mensagens
devem incluir chave em inglês e tradução pt-BR no catálogo. Os testes tradicionais rodam em pt-BR
pois algumas asserções verificam mensagens; os testes de localização também verificam os dois idiomas.

## Compatibilidade

Projeto, target, scheme, módulo e pastas de código permanecem **PhotoImporter**. Isso evita
renomeações cosméticas e mantém `@testable import PhotoImporter`. O produto/executável, os nomes
visíveis, o menu do aplicativo, a janela Sobre, o pacote e o host dos testes usam **Roll**.

Permanecem inalterados: Bundle Identifier `local.lucas.PhotoImporter`, UserDefaults/keys,
security-scoped bookmarks, `PhotoImporter/Imports`, schemas JSON, identidades, locks e nomes
`.photoimporter-*.partial`. Valores raw dos enums antigos são mantidos e recebem rótulos localizados.
Não há migração de dados, nova organização de arquivos, alteração no agrupamento ou nas regras de cópia.
O nome Roll representa uma sessão de importação, não um catálogo proprietário ou uma pasta adicional.

Ao instalar Roll, remover manualmente a cópia antiga `PhotoImporter.app` apenas depois de encerrar
operações; não manter duas cópias com o mesmo Bundle Identifier em uso. O empacotamento não apaga
nem substitui automaticamente um app instalado ou um DMG anterior.

## Ícone provisório e arte definitiva

A primeira imagem enviada pelo usuário foi aprovada como ícone **provisório** do Roll.
O PNG original de 1024 × 1024 está preservado, sem alteração de arte, em
[branding/roll-provisional-source.png](branding/roll-provisional-source.png).
O fundo branco e a composição da imagem foram mantidos; não houve recorte ou geração de nova arte.

`PhotoImporter/Assets.xcassets/AppIcon.appiconset` contém os dez slots nativos de macOS,
de 16 × 16 a 1024 × 1024 pixels (incluindo @2x), exportados com `sips`.
Debug e Release usam `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. Xcode gera o `.icns`
e os metadados do bundle. A janela Sobre usa o ícone do próprio aplicativo, assim como Finder e Dock.
A versão 0.1.1 (build 2) identifica o primeiro pacote com ícone, preservando os DMGs anteriores.

A arte definitiva continua pendente: cartucho 35 mm em carvão, rótulo âmbar, fundo marfim,
tira perfurada, profundidade sutil e silhueta legível em tamanhos pequenos. Sem logos de fabricantes,
câmeras genéricas, setas de download, textos longos ou aparência de emoji. A segunda imagem
continua como referência, sem substituir o ícone aprovado provisoriamente.

Para substituir a arte, preencher os mesmos slots com PNGs correspondentes, mantendo Bundle Identifier,
persistência e regras de segurança. Validar tamanhos pequenos, Finder, Dock e Sobre em claro/escuro.
