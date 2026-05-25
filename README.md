<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>2LOCK — Zabbix Agent Deploy</title>
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600&family=Sora:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  :root {
    --blue-dark:    #1B2B6B;
    --blue-mid:     #2D52C4;
    --blue-light:   #4FC3E8;
    --blue-pale:    #E8F0FB;
    --white:        #FFFFFF;
    --text-body:    #2C3A5C;
    --text-muted:   #6B7CA4;
    --border:       #CBD5EF;
    --surface:      #F4F7FF;
    --code-bg:      #0D1B4B;
    --code-text:    #A8C4FF;
  }

  body {
    font-family: 'Sora', sans-serif;
    background: var(--surface);
    color: var(--text-body);
    min-height: 100vh;
  }

  /* ── HEADER ── */
  header {
    background: var(--blue-dark);
    padding: 40px 0 0;
    text-align: center;
    position: relative;
    overflow: hidden;
  }

  header::before {
    content: '';
    position: absolute;
    inset: 0;
    background:
      radial-gradient(ellipse at 20% 50%, rgba(79,195,232,0.12) 0%, transparent 60%),
      radial-gradient(ellipse at 80% 20%, rgba(45,82,196,0.25) 0%, transparent 55%);
  }

  .header-inner {
    position: relative;
    z-index: 1;
    max-width: 860px;
    margin: 0 auto;
    padding: 0 32px 40px;
  }

  .logo-wrap {
    display: inline-block;
    background: white;
    border-radius: 14px;
    padding: 12px 24px;
    margin-bottom: 28px;
  }

  .logo-wrap img { height: 36px; display: block; }

  header h1 {
    font-size: 13px;
    font-weight: 600;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--blue-light);
    margin-bottom: 10px;
  }

  header h2 {
    font-size: 30px;
    font-weight: 700;
    color: var(--white);
    line-height: 1.25;
    margin-bottom: 14px;
  }

  header p {
    font-size: 15px;
    color: rgba(255,255,255,0.65);
    max-width: 520px;
    margin: 0 auto 28px;
    line-height: 1.6;
  }

  .badge-row {
    display: flex;
    gap: 10px;
    justify-content: center;
    flex-wrap: wrap;
  }

  .badge {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    background: rgba(255,255,255,0.08);
    border: 1px solid rgba(79,195,232,0.3);
    border-radius: 100px;
    padding: 5px 14px;
    font-size: 12px;
    font-weight: 500;
    color: var(--blue-light);
    letter-spacing: 0.02em;
  }

  .header-tabs {
    display: flex;
    justify-content: center;
    gap: 0;
    margin-top: 36px;
    border-top: 1px solid rgba(255,255,255,0.08);
  }

  .header-tab {
    padding: 14px 28px;
    font-size: 13px;
    font-weight: 500;
    color: rgba(255,255,255,0.45);
    border-bottom: 2px solid transparent;
    letter-spacing: 0.03em;
  }

  /* ── LAYOUT ── */
  main {
    max-width: 860px;
    margin: 0 auto;
    padding: 48px 32px 80px;
  }

  /* ── SECTION TITLE ── */
  .section-label {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-bottom: 20px;
    margin-top: 52px;
  }

  .section-label:first-child { margin-top: 0; }

  .section-label .dot {
    width: 8px; height: 8px;
    border-radius: 50%;
    background: var(--blue-light);
    flex-shrink: 0;
  }

  .section-label h3 {
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    color: var(--blue-mid);
  }

  .section-label::after {
    content: '';
    flex: 1;
    height: 1px;
    background: var(--border);
  }

  /* ── ESTRUTURA DO REPO ── */
  .repo-tree {
    background: var(--code-bg);
    border-radius: 12px;
    padding: 24px 28px;
    font-family: 'JetBrains Mono', monospace;
    font-size: 13px;
    color: var(--code-text);
    line-height: 1.9;
    border: 1px solid rgba(79,195,232,0.15);
    overflow-x: auto;
  }

  .repo-tree .tree-dir  { color: #7EB8FF; font-weight: 600; }
  .repo-tree .tree-file { color: #A8C4FF; }
  .repo-tree .tree-comment { color: #4FC3E8; opacity: 0.7; }

  /* ── OS CARDS ── */
  .os-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 20px;
  }

  @media (max-width: 600px) { .os-grid { grid-template-columns: 1fr; } }

  .os-card {
    background: white;
    border: 1px solid var(--border);
    border-radius: 14px;
    padding: 24px;
    position: relative;
    overflow: hidden;
  }

  .os-card::before {
    content: '';
    position: absolute;
    top: 0; left: 0; right: 0;
    height: 3px;
    background: linear-gradient(90deg, var(--blue-dark), var(--blue-light));
  }

  .os-card h4 {
    font-size: 16px;
    font-weight: 700;
    color: var(--blue-dark);
    margin-bottom: 4px;
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .os-icon {
    width: 28px; height: 28px;
    background: var(--blue-pale);
    border-radius: 6px;
    display: flex; align-items: center; justify-content: center;
    font-size: 16px;
  }

  .os-card .compat {
    font-size: 12px;
    color: var(--text-muted);
    margin-bottom: 16px;
  }

  /* ── CODE BLOCKS ── */
  .code-block {
    background: var(--code-bg);
    border-radius: 10px;
    overflow: hidden;
    margin-bottom: 14px;
    border: 1px solid rgba(79,195,232,0.12);
  }

  .code-block-label {
    background: rgba(79,195,232,0.08);
    border-bottom: 1px solid rgba(79,195,232,0.12);
    padding: 7px 14px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.08em;
    color: var(--blue-light);
    text-transform: uppercase;
    font-family: 'JetBrains Mono', monospace;
  }

  .code-block pre {
    padding: 14px 16px;
    font-family: 'JetBrains Mono', monospace;
    font-size: 12.5px;
    color: #c8daff;
    line-height: 1.7;
    overflow-x: auto;
    white-space: pre;
  }

  .code-block pre .cmd  { color: #4FC3E8; }
  .code-block pre .flag { color: #7EB8FF; }
  .code-block pre .val  { color: #9EFFD0; }
  .code-block pre .comment { color: #4a6aaa; font-style: italic; }

  /* ── STEPS ── */
  .steps {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .step {
    display: flex;
    gap: 14px;
    align-items: flex-start;
  }

  .step-num {
    width: 26px; height: 26px;
    border-radius: 50%;
    background: var(--blue-dark);
    color: white;
    font-size: 11px;
    font-weight: 700;
    display: flex; align-items: center; justify-content: center;
    flex-shrink: 0;
    margin-top: 1px;
  }

  .step p { font-size: 14px; line-height: 1.5; color: var(--text-body); }
  .step code {
    font-family: 'JetBrains Mono', monospace;
    font-size: 12px;
    background: var(--blue-pale);
    color: var(--blue-dark);
    padding: 1px 6px;
    border-radius: 4px;
  }

  /* ── CALLOUT ── */
  .callout {
    display: flex;
    gap: 12px;
    align-items: flex-start;
    background: #EBF4FD;
    border: 1px solid #BADDF5;
    border-left: 3px solid var(--blue-mid);
    border-radius: 8px;
    padding: 12px 16px;
    margin: 14px 0;
    font-size: 13.5px;
    color: var(--blue-dark);
    line-height: 1.55;
  }

  .callout-icon { font-size: 16px; flex-shrink: 0; margin-top: 1px; }

  /* ── TABELA ── */
  .styled-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13.5px;
  }

  .styled-table thead tr {
    background: var(--blue-dark);
  }

  .styled-table thead th {
    padding: 11px 16px;
    text-align: left;
    color: rgba(255,255,255,0.75);
    font-weight: 600;
    font-size: 11px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
  }

  .styled-table thead th:first-child { border-radius: 8px 0 0 0; }
  .styled-table thead th:last-child  { border-radius: 0 8px 0 0; }

  .styled-table tbody tr {
    border-bottom: 1px solid var(--border);
    background: white;
  }

  .styled-table tbody tr:hover { background: var(--blue-pale); }

  .styled-table td {
    padding: 10px 16px;
    color: var(--text-body);
    vertical-align: middle;
  }

  .status-ok {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    background: #E6F4EB;
    color: #1A7A3E;
    font-size: 12px;
    font-weight: 600;
    padding: 3px 10px;
    border-radius: 100px;
  }

  .status-wip {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    background: #FFF4E0;
    color: #9A6200;
    font-size: 12px;
    font-weight: 600;
    padding: 3px 10px;
    border-radius: 100px;
  }

  /* ── PLUGIN CARDS ── */
  .plugin-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 14px;
  }

  @media (max-width: 600px) { .plugin-grid { grid-template-columns: 1fr; } }

  .plugin-card {
    background: white;
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 18px;
    text-align: center;
  }

  .plugin-icon {
    font-size: 28px;
    margin-bottom: 10px;
  }

  .plugin-card h5 {
    font-size: 14px;
    font-weight: 700;
    color: var(--blue-dark);
    margin-bottom: 4px;
  }

  .plugin-card p {
    font-size: 12px;
    color: var(--text-muted);
  }

  .plugin-badge {
    display: inline-block;
    margin-top: 8px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.06em;
    padding: 3px 10px;
    border-radius: 100px;
    background: var(--blue-pale);
    color: var(--blue-mid);
    text-transform: uppercase;
  }

  /* ── PREREQS ── */
  .prereq-list {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
  }

  @media (max-width: 600px) { .prereq-list { grid-template-columns: 1fr; } }

  .prereq-item {
    display: flex;
    align-items: center;
    gap: 10px;
    background: white;
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 12px 16px;
    font-size: 13.5px;
    color: var(--text-body);
  }

  .prereq-item .prereq-icon {
    font-size: 18px;
    flex-shrink: 0;
  }

  /* ── FOOTER ── */
  footer {
    background: var(--blue-dark);
    text-align: center;
    padding: 32px;
    color: rgba(255,255,255,0.45);
    font-size: 13px;
  }

  footer a { color: var(--blue-light); text-decoration: none; }
  footer strong { color: rgba(255,255,255,0.7); }

  /* ── WHAT IT DOES LIST ── */
  .does-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .does-item {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    font-size: 13.5px;
    color: var(--text-body);
    line-height: 1.5;
  }

  .does-item::before {
    content: '▸';
    color: var(--blue-light);
    font-size: 12px;
    margin-top: 3px;
    flex-shrink: 0;
  }
</style>
</head>
<body>

<!-- ═══════════════ HEADER ═══════════════ -->
<header>
  <div class="header-inner">
    <div class="logo-wrap">
      <img src="https://2lock.com.br/wp-content/uploads/2024/10/logo.webp" alt="2LOCK">
    </div>
    <h1>Infraestrutura &amp; Monitoramento</h1>
    <h2>Zabbix Agent Deploy</h2>
    <p>Scripts e guias para instalação e configuração automatizada do Zabbix Agent 2 em ambientes Linux e Windows.</p>
    <div class="badge-row">
      <span class="badge">⬡ Zabbix 7.0 LTS</span>
      <span class="badge">🐧 Linux</span>
      <span class="badge">🪟 Windows Server</span>
      <span class="badge">⚙ Automatizado</span>
    </div>
    <div class="header-tabs">
      <span class="header-tab">Linux</span>
      <span class="header-tab">Windows</span>
      <span class="header-tab">Plugins</span>
      <span class="header-tab">Referência</span>
    </div>
  </div>
</header>

<!-- ═══════════════ MAIN ═══════════════ -->
<main>

  <!-- ESTRUTURA -->
  <div class="section-label"><div class="dot"></div><h3>Estrutura do Repositório</h3></div>

  <div class="repo-tree">
<span class="tree-dir">zabbix-agent-deploy/</span>
│
├── <span class="tree-dir">linux/</span>
│   ├── <span class="tree-file">zabbix_agent2_install.sh</span>   <span class="tree-comment">← Instalador automatizado</span>
│   ├── <span class="tree-file">README.md</span>                  <span class="tree-comment">← Instruções e parâmetros</span>
│   └── <span class="tree-dir">plugins/</span>
│       └── <span class="tree-file">mysql.md</span>               <span class="tree-comment">← Configuração do plugin MySQL</span>
│
└── <span class="tree-dir">windows/</span>
    ├── <span class="tree-file">zabbix_agent2_install.ps1</span>  <span class="tree-comment">← Instalador automatizado (PowerShell)</span>
    ├── <span class="tree-file">README.md</span>                  <span class="tree-comment">← Instruções e parâmetros</span>
    └── <span class="tree-dir">plugins/</span>
        └── <span class="tree-file">mssql.md</span>               <span class="tree-comment">← Configuração do plugin MSSQL</span></div>

  <div class="callout">
    <span class="callout-icon">💡</span>
    Cada pasta é <strong>autossuficiente</strong> — tudo que você precisa para instalar e configurar o agente em um determinado sistema operacional está dentro da pasta correspondente.
  </div>

  <!-- OS CARDS -->
  <div class="section-label"><div class="dot"></div><h3>Instalação Rápida</h3></div>

  <div class="os-grid">
    <!-- LINUX -->
    <div class="os-card">
      <h4><div class="os-icon">🐧</div> Linux</h4>
      <p class="compat">AlmaLinux · RHEL · Rocky · Ubuntu · Debian — x86_64 &amp; aarch64</p>

      <div class="code-block">
        <div class="code-block-label">via 2LOCK (recomendado)</div>
        <pre><span class="cmd">curl</span> <span class="flag">-fsSL</span> <span class="val">https://2lock.com.br/linuxagent</span> | <span class="cmd">sudo bash</span></pre>
      </div>

      <div class="code-block">
        <div class="code-block-label">Download direto do GitHub</div>
        <pre><span class="cmd">curl</span> <span class="flag">-O</span> <span class="val">https://raw.githubusercontent.com/\</span>
  2lock/zabbix-agent-deploy/main/\
  linux/zabbix_agent2_install.sh
<span class="cmd">chmod</span> +x zabbix_agent2_install.sh
<span class="cmd">sudo</span> ./zabbix_agent2_install.sh</pre>
      </div>

      <div class="code-block">
        <div class="code-block-label">Modo automatizado (--auto)</div>
        <pre><span class="cmd">sudo</span> <span class="flag">ACCEPT_EULA</span>=<span class="val">yes</span> \
     <span class="flag">ZABBIX_SERVER</span>=<span class="val">10.0.0.1</span> \
     <span class="flag">ZABBIX_PORT</span>=<span class="val">10050</span> \
     <span class="flag">ZABBIX_HOSTNAME</span>=<span class="val">MEUSERVIDOR</span> \
     <span class="flag">APPLY_FIREWALL</span>=<span class="val">yes</span> \
     bash &lt;(curl -fsSL \
       https://2lock.com.br/linuxagent) \
     <span class="flag">--auto</span></pre>
      </div>
    </div>

    <!-- WINDOWS -->
    <div class="os-card">
      <h4><div class="os-icon">🪟</div> Windows</h4>
      <p class="compat">Windows Server 2016 · 2019 · 2022 — x86_64</p>

      <div class="code-block">
        <div class="code-block-label">PowerShell como Administrador (recomendado)</div>
        <pre><span class="cmd">iwr</span> <span class="val">https://2lock.com.br/windowsagent</span> | <span class="cmd">iex</span></pre>
      </div>

      <div class="code-block">
        <div class="code-block-label">Modo automatizado</div>
        <pre><span class="flag">$env:ACCEPT_EULA</span>     = <span class="val">"yes"</span>
<span class="flag">$env:ZABBIX_SERVER</span>   = <span class="val">"10.0.0.1"</span>
<span class="flag">$env:ZABBIX_PORT</span>     = <span class="val">"10050"</span>
<span class="flag">$env:ZABBIX_HOSTNAME</span> = <span class="val">"MEUSERVIDOR"</span>
<span class="flag">$env:APPLY_FIREWALL</span>  = <span class="val">"yes"</span>
<span class="cmd">iwr</span> <span class="val">https://2lock.com.br/windowsagent</span> | <span class="cmd">iex</span></pre>
      </div>

      <div style="margin-top:16px;">
        <div class="steps">
          <div class="step"><div class="step-num">i</div><p>Execute o PowerShell <strong>como Administrador</strong> antes de rodar o script</p></div>
          <div class="step"><div class="step-num">i</div><p>Veja o <code>windows/README.md</code> para parâmetros completos</p></div>
        </div>
      </div>
    </div>
  </div>

  <!-- O QUE OS INSTALADORES FAZEM -->
  <div class="section-label"><div class="dot"></div><h3>O que os instaladores fazem</h3></div>

  <div class="os-grid">
    <div class="os-card">
      <h4><div class="os-icon">🐧</div> Linux</h4>
      <p class="compat" style="margin-bottom:14px;">Processo completo e automatizado</p>
      <div class="does-list">
        <div class="does-item">Detecta distribuição e arquitetura (x86_64 / aarch64)</div>
        <div class="does-item">Verifica sincronismo NTP antes de instalar</div>
        <div class="does-item">Remove versões anteriores do agente</div>
        <div class="does-item">Configura repositório oficial Zabbix 7.0</div>
        <div class="does-item">Instala Zabbix Agent 2 e plugins opcionais</div>
        <div class="does-item">Adiciona usuário <code style="font-family:monospace;font-size:12px;background:#EEF2FF;color:#1B2B6B;padding:1px 5px;border-radius:4px;">zabbix</code> ao grupo <code style="font-family:monospace;font-size:12px;background:#EEF2FF;color:#1B2B6B;padding:1px 5px;border-radius:4px;">docker</code> se aplicável</div>
        <div class="does-item">Configura user parameter <code style="font-family:monospace;font-size:12px;background:#EEF2FF;color:#1B2B6B;padding:1px 5px;border-radius:4px;">linux.top.cpu</code></div>
        <div class="does-item">Aplica regra de firewall restrita ao IP do servidor</div>
        <div class="does-item">Valida instalação e gera log completo</div>
      </div>
    </div>
    <div class="os-card">
      <h4><div class="os-icon">🪟</div> Windows</h4>
      <p class="compat" style="margin-bottom:14px;">Processo completo e automatizado</p>
      <div class="does-list">
        <div class="does-item">Baixa o instalador MSI oficial do Zabbix 7.0</div>
        <div class="does-item">Instala e configura o Zabbix Agent 2 como serviço Windows</div>
        <div class="does-item">Configura porta de escuta e hostname</div>
        <div class="does-item">Aplica regra de firewall restrita ao IP do Zabbix Server</div>
        <div class="does-item">Valida o serviço e a conectividade</div>
      </div>
    </div>
  </div>

  <!-- PLUGINS -->
  <div class="section-label"><div class="dot"></div><h3>Plugins disponíveis</h3></div>

  <div class="plugin-grid">
    <div class="plugin-card">
      <div class="plugin-icon">🐬</div>
      <h5>MySQL</h5>
      <p>Monitoramento de bancos de dados MySQL via plugin nativo</p>
      <span class="plugin-badge">Linux</span>
    </div>
    <div class="plugin-card">
      <div class="plugin-icon">🗄</div>
      <h5>MSSQL</h5>
      <p>Monitoramento de bancos de dados SQL Server via plugin</p>
      <span class="plugin-badge">Windows</span>
    </div>
    <div class="plugin-card">
      <div class="plugin-icon">🐳</div>
      <h5>Docker</h5>
      <p>Monitoramento de containers via grupo docker — automático</p>
      <span class="plugin-badge">Linux</span>
    </div>
  </div>

  <!-- SISTEMAS TESTADOS -->
  <div class="section-label"><div class="dot"></div><h3>Sistemas testados</h3></div>

  <div style="border-radius:12px; overflow:hidden; border:1px solid var(--border);">
    <table class="styled-table">
      <thead>
        <tr>
          <th>Sistema Operacional</th>
          <th>Versão</th>
          <th>Arquitetura</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>
        <tr><td>AlmaLinux</td><td>9.x</td><td>x86_64</td><td><span class="status-ok">✓ Validado</span></td></tr>
        <tr><td>AlmaLinux</td><td>8.x</td><td>x86_64</td><td><span class="status-ok">✓ Validado</span></td></tr>
        <tr><td>RHEL</td><td>9.x</td><td>x86_64</td><td><span class="status-ok">✓ Validado</span></td></tr>
        <tr><td>Rocky Linux</td><td>9.x</td><td>x86_64</td><td><span class="status-ok">✓ Validado</span></td></tr>
        <tr><td>Ubuntu</td><td>22.04 LTS</td><td>x86_64</td><td><span class="status-ok">✓ Validado</span></td></tr>
        <tr><td>Ubuntu</td><td>20.04 LTS</td><td>x86_64</td><td><span class="status-ok">✓ Validado</span></td></tr>
        <tr><td>Debian</td><td>11 / 12</td><td>x86_64</td><td><span class="status-ok">✓ Validado</span></td></tr>
        <tr><td>Windows Server</td><td>2022</td><td>x86_64</td><td><span class="status-wip">⏳ Em breve</span></td></tr>
        <tr><td>Windows Server</td><td>2019</td><td>x86_64</td><td><span class="status-wip">⏳ Em breve</span></td></tr>
      </tbody>
    </table>
  </div>

  <!-- PRÉ-REQUISITOS -->
  <div class="section-label"><div class="dot"></div><h3>Pré-requisitos gerais</h3></div>

  <div class="prereq-list">
    <div class="prereq-item"><span class="prereq-icon">🔑</span> Acesso root (Linux) ou Administrador (Windows)</div>
    <div class="prereq-item"><span class="prereq-icon">🌐</span> Conectividade HTTPS com <code style="font-family:monospace;font-size:12px;background:#EEF2FF;color:#1B2B6B;padding:1px 5px;border-radius:4px;">repo.zabbix.com</code></div>
    <div class="prereq-item"><span class="prereq-icon">📡</span> IP do Zabbix Server acessível na rede</div>
    <div class="prereq-item"><span class="prereq-icon">🕐</span> NTP ativo no servidor (recomendado)</div>
  </div>

</main>

<!-- ═══════════════ FOOTER ═══════════════ -->
<footer>
  <img src="https://2lock.com.br/wp-content/uploads/2024/10/logo.webp" alt="2LOCK" style="height:24px;opacity:0.6;margin-bottom:12px;display:block;margin-left:auto;margin-right:auto;">
  <p>Scripts mantidos pela equipe de infraestrutura da <strong>2LOCK</strong>.</p>
  <p style="margin-top:6px;">Sugestões ou correções? <a href="https://2lock.com.br/contato/">https://2lock.com.br/contato/</a></p>
  <p style="margin-top:6px; font-size:12px;">Uso permitido em ambientes sob gestão da 2LOCK. Para outros fins, entre em contato.</p>
</footer>

</body>
</html>
