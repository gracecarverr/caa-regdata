# =========================================================================================================
# code/diagnostics/site_shell.R \u2014 shared header/nav/hero/footer chrome + CSS design system for the public
#   docs/ site (Home, Raw Data, Databases, Panels). Sourced by each page's build script alongside
#   tables/_html.R (esc(), comma(), pct1(), dollar()). Contains NO computed numbers \u2014 chrome only.
# =========================================================================================================

NAV_ITEMS <- list(
  list(id = "home",      href = "index.html",     label = "Home"),
  list(id = "raw_data",  href = "raw_data.html",  label = "Raw Data"),
  list(id = "databases", href = "databases.html", label = "Databases"),
  list(id = "panels",    href = "panels.html",    label = "Panels")
)

site_nav <- function(active) {
  links <- vapply(NAV_ITEMS, function(n) {
    cls <- if (identical(n$id, active)) " class='active'" else ""
    sprintf("<a href='%s'%s>%s</a>", n$href, cls, esc(n$label))
  }, character(1))
  paste0("<nav class='site-nav'>", paste(links, collapse = ""), "</nav>")
}

site_header <- function(active) paste0(
  "<header class='site-header'><div class='site-header-inner'>",
  "<a class='site-brand' href='index.html'>CAA Regulatory Data</a>",
  site_nav(active),
  "</div></header>")

# eyebrow: small caps label above the title (optional). title/desc: plain text, escaped here.
# bg_image: optional path (relative to docs/, e.g. "images/hero-smokestack.jpg") for a photo hero instead of
# the plain navy gradient; photo_credit: optional plain-text attribution shown small, bottom-right of the
# hero (public-domain photos don't legally require credit, but citing the source is good practice for a
# reproducibility-minded site). A dark gradient is layered UNDER the photo (not the photo behind a solid
# gradient) so the existing white hero text stays readable without needing per-photo contrast tuning.
hero <- function(title, desc = NULL, eyebrow = NULL, bg_image = NULL, photo_credit = NULL) paste0(
  "<div class='hero", if (!is.null(bg_image)) " hero-photo" else "", "'",
  if (!is.null(bg_image)) paste0(" style=\"background-image:linear-gradient(160deg,rgba(0,51,73,.88) 0%,rgba(0,31,46,.92) 100%),url('", bg_image, "')\"") else "",
  "><div class='hero-inner'>",
  if (!is.null(eyebrow)) paste0("<p class='eyebrow'>", esc(eyebrow), "</p>") else "",
  "<h1>", esc(title), "</h1>",
  if (!is.null(desc)) paste0("<p>", esc(desc), "</p>") else "",
  if (!is.null(photo_credit)) paste0("<p class='photo-credit'>", esc(photo_credit), "</p>") else "",
  "</div></div>")

page_main <- function(...) paste0("<main>", paste0(..., collapse = ""), "</main>")

card <- function(title, desc, href, cta = "View \u2192") paste0(
  "<div class='card'><h3>", esc(title), "</h3><p>", esc(desc), "</p>",
  "<a href='", href, "'>", esc(cta), "</a></div>")

cards <- function(...) paste0("<div class='cards'>", paste0(..., collapse = ""), "</div>")

# doc_nav(): shared docs-site-style sidebar + content-pane component (Home's institutional-overview
# sections, Raw Data's per-source sections). `sections` is a list of list(id=, title=, body_html=)
# elements: `id` becomes the sidebar link's #hash target and the pane's element id (must be unique on the
# page and URL-fragment-safe -- callers slugify their own titles into this); `title` is the sidebar label
# (plain text, escaped here); `body_html` is that section's own already-rendered HTML, shown under a plain
# <h2> heading -- deliberately NOT a dedicated CSS class: every pane's <h2> is structurally the first child
# of its .doc-pane, so the existing `.prose h2` / `.prose h2:first-child` rules already style it exactly
# right (no extra top border/margin, since :first-child always matches here) with no new selector needed.
# Only one pane is visible at a time -- doc_nav_script() below wires the click-to-switch behavior and #hash
# deep-linking generically, once, for every .doc-nav block on the page (there's no static-HTML-only way to
# do a click-to-switch sidebar, unlike everything else on this site).
doc_nav <- function(sections) {
  links <- vapply(sections, function(s) sprintf(
    "<a href='#%s' class='doc-sidebar-link' data-target='%s'>%s</a>", s$id, s$id, esc(s$title)
  ), character(1))
  panes <- vapply(sections, function(s) sprintf(
    "<div class='doc-pane' id='%s'><h2>%s</h2>%s</div>",
    s$id, esc(s$title), s$body_html
  ), character(1))
  paste0(
    "<div class='doc-nav'>",
    "<nav class='doc-sidebar'>", paste(links, collapse = ""), "</nav>",
    "<div class='doc-content'>", paste(panes, collapse = ""), "</div>",
    "</div>"
  )
}

# Vanilla JS, no dependencies: for every .doc-nav block on the page, show exactly one .doc-pane at a time
# (the one matching the clicked sidebar link's data-target, or the URL's #hash on load, or the first pane
# as a fallback so the content area is never empty). Uses history.replaceState (not location.hash directly)
# so clicking a link doesn't add a new browser-history entry per click.
DOC_NAV_SCRIPT <- "<script>
(function(){
  document.querySelectorAll('.doc-nav').forEach(function(nav){
    var links = nav.querySelectorAll('.doc-sidebar-link');
    var panes = nav.querySelectorAll('.doc-pane');
    function show(id){
      links.forEach(function(l){ l.classList.toggle('active', l.dataset.target === id); });
      panes.forEach(function(p){ p.hidden = (p.id !== id); });
    }
    links.forEach(function(l){
      l.addEventListener('click', function(e){
        e.preventDefault();
        history.replaceState(null, '', '#' + l.dataset.target);
        show(l.dataset.target);
      });
    });
    var initial = (location.hash || '').slice(1);
    if (!initial || !nav.querySelector(\"[id='\" + initial + \"']\")) initial = links.length ? links[0].dataset.target : null;
    if (initial) show(initial);
  });
})();
</script>"

site_footer <- function() paste0(
  "<footer class='site-footer'><p>Automatically generated from the underlying data \u2014 no figures are ",
  "hand-entered. Part of the <a href='https://github.com/gracecarverr/caa-regdata'>caa-regdata</a> ",
  "reproducible pipeline.</p></footer>")

# title: page title (used in <title> + meta); description: one-line meta description (plain text);
# active: one of NAV_ITEMS[[i]]$id; body_html: hero() + page_main(...) already assembled by the caller.
site_shell <- function(title, description, active, body_html) paste0(
  "<!doctype html><html lang='en'><head><meta charset='utf-8'>",
  "<meta name='viewport' content='width=device-width,initial-scale=1'>",
  "<title>", esc(title), " \u2014 CAA Regulatory Data</title>",
  if (!is.null(description)) paste0("<meta name='description' content=\"", esc(description), "\">") else "",
  SITE_FONTS,
  "<style>", SITE_CSS, "</style></head><body>",
  site_header(active),
  body_html,
  site_footer(),
  DOC_NAV_SCRIPT,
  "</body></html>")

# ---- design system -------------------------------------------------------------------------------------
# Matches epicforamerica.org's actual design tokens (Economic Policy Innovation Center), pulled from that
# site's live theme-options CSS custom properties on 2026-07-28, not guessed from a screenshot: navy
# #003349 (primary), burgundy-mauve #933f71 (secondary/links, hover #612141), Merriweather (serif,
# weight 300 -- a LIGHT serif, not bold) for headings, Merriweather Sans (weight 300 body / 700 bold) for
# copy, 0px border-radius everywhere. Their own homepage hero is a photographic Capitol-dome banner; we
# have no rights to that image and no equivalent asset, so our hero stays a solid/gradient navy band
# instead of a photo -- a deliberate, documented gap, not an oversight. The raw-data page's existing table
# styling (.cat/.num headers, etc.) is scoped under .raw-data so it can't collide with this chrome.
SITE_FONTS <- paste0(
  "<link rel='preconnect' href='https://fonts.googleapis.com'>",
  "<link rel='preconnect' href='https://fonts.gstatic.com' crossorigin>",
  "<link href='https://fonts.googleapis.com/css2?family=Merriweather:wght@300;700&",
  "family=Merriweather+Sans:wght@300;600;700&display=swap' rel='stylesheet'>")
SITE_CSS <- "
:root{
  --navy:#003349; --navy-dark:#001f2e; --accent:#933f71; --accent-dark:#612141;
  --bg:#ffffff; --bg-alt:#f2f4f7; --ink:#0f131f; --text:#333333; --muted:#727f9f; --border:#e3e7f0;
}
*{box-sizing:border-box;}
body{margin:0;font-family:'Merriweather Sans',system-ui,sans-serif;font-weight:300;color:var(--text);
  background:var(--bg);}
a{color:var(--accent);}

.site-header{background:#fff;border-bottom:1px solid var(--border);}
.site-header-inner{max-width:1100px;margin:0 auto;padding:.9rem 1.2rem;display:flex;align-items:center;
  justify-content:space-between;flex-wrap:wrap;gap:.5rem 1.2rem;}
.site-brand{font-family:'Merriweather',Georgia,serif;font-weight:300;font-size:1.2rem;
  color:var(--navy);text-decoration:none;letter-spacing:.01em;}
.site-nav{display:flex;gap:1.5rem;font-weight:600;font-size:.92rem;flex-wrap:wrap;}
.site-nav a{color:var(--accent);text-decoration:none;padding:.15rem 0;border-bottom:2px solid transparent;}
.site-nav a:hover{color:var(--accent-dark);border-bottom-color:var(--accent-dark);}
.site-nav a.active{color:var(--navy);border-bottom-color:var(--accent-dark);}

.hero{background:linear-gradient(160deg,var(--navy) 0%,var(--navy-dark) 100%);color:#fff;
  padding:3rem 1.2rem 2.4rem;}
.hero-photo{background-size:cover;background-position:center 30%;padding:5rem 1.2rem 3.2rem;}
.hero-inner{max-width:1100px;margin:0 auto;position:relative;}
.hero .eyebrow{text-transform:uppercase;letter-spacing:.13em;font-size:.76rem;color:rgba(255,255,255,.66);
  font-weight:700;margin:0 0 .7rem;}
.hero h1{font-family:'Merriweather',Georgia,serif;font-weight:300;font-size:2.5rem;
  line-height:1.18;margin:0 0 .7rem;}
.hero p{font-size:1.05rem;max-width:760px;color:#dde1ec;margin:0;line-height:1.55;}
.hero .photo-credit{font-size:.7rem;color:rgba(255,255,255,.55);max-width:none;margin:1.6rem 0 0;
  font-style:italic;}

main{max-width:1100px;margin:0 auto;padding:2.4rem 1.2rem 3rem;}

.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:1.1rem;margin:1.6rem 0 2.4rem;}
.card{border:1px solid var(--border);border-top:3px solid var(--navy);background:#fff;padding:1.2rem 1.3rem;}
.card h3{font-family:'Merriweather',Georgia,serif;font-weight:300;margin:.1rem 0 .4rem;font-size:1.15rem;
  color:var(--navy);}
.card p{font-size:.92rem;color:var(--muted);margin:0 0 .8rem;line-height:1.45;}
.card a{color:var(--accent);font-weight:600;font-size:.88rem;text-decoration:none;}
.card a:hover{color:var(--accent-dark);text-decoration:underline;}

.prose h2{font-family:'Merriweather',Georgia,serif;font-weight:300;color:var(--navy);
  border-top:1px solid var(--border);padding-top:1.6rem;margin-top:2.4rem;font-size:1.5rem;text-align:left;}
.prose h2:first-child{border-top:none;padding-top:0;margin-top:0;}
.prose h3{font-family:'Merriweather',Georgia,serif;font-weight:300;color:var(--navy);margin-top:1.7rem;
  font-size:1.18rem;}
.prose p,.prose li{line-height:1.62;}
.prose blockquote{border-left:3px solid var(--accent);margin:1.1rem 0;padding:.35rem 1.1rem;color:var(--muted);
  background:var(--bg-alt);}
.prose table{border-collapse:collapse;width:100%;margin:1rem 0;font-size:.92em;}
.prose th,.prose td{border:1px solid var(--border);padding:.5rem .7rem;text-align:left;vertical-align:top;}
.prose th{background:var(--bg-alt);}
.prose code{font-family:ui-monospace,Menlo,monospace;background:var(--bg-alt);padding:.05rem .3rem;font-size:.9em;}

/* ---- doc-nav (Home's institutional-overview sections, Raw Data's per-source sections): docs-site-style
   sidebar + content pane. One title list on the left (sticky), one pane visible at a time on the right.
   Needs doc_nav_script (below) to switch panes and support #hash deep-linking -- everything else on this
   site is plain HTML/CSS with no JS, but a click-to-switch sidebar has no static-HTML equivalent. ------- */
.doc-nav{display:flex;gap:2.2rem;align-items:flex-start;margin-top:.4rem;}
.doc-sidebar{flex:0 0 230px;display:flex;flex-direction:column;gap:.1rem;position:sticky;top:1rem;
  border-right:1px solid var(--border);padding-right:1.1rem;}
.doc-sidebar-link{display:block;padding:.6rem .7rem;color:var(--text);text-decoration:none;font-size:.93rem;
  border-left:3px solid transparent;transition:background-color .15s ease,color .15s ease,border-color .15s ease;}
.doc-sidebar-link:hover{background:var(--bg-alt);color:var(--navy);}
.doc-sidebar-link.active{background:var(--bg-alt);color:var(--accent);border-left-color:var(--accent);font-weight:600;}
.doc-content{flex:1;min-width:0;overflow-x:auto;}
@media (max-width:820px){
  .doc-nav{flex-direction:column;gap:0;}
  .doc-sidebar{flex:none;position:static;top:auto;flex-direction:row;flex-wrap:wrap;gap:.3rem;
    border-right:none;border-bottom:1px solid var(--border);padding:0 0 .8rem;margin-bottom:1rem;}
  .doc-sidebar-link{border-left:none;border-bottom:3px solid transparent;padding:.4rem .6rem;}
  .doc-sidebar-link.active{border-left-color:transparent;border-bottom-color:var(--accent);}
}

.section-note{background:var(--bg-alt);border:1px solid var(--border);border-left:3px solid var(--accent);
  padding:.9rem 1.1rem;margin:1.4rem 0;font-size:.92em;line-height:1.55;}

.stat-table{border-collapse:collapse;width:100%;margin:.6rem 0 .5rem;font-size:.9em;}
.stat-table th,.stat-table td{border:1px solid var(--border);padding:.45rem .7rem;text-align:right;}
.stat-table th{background:var(--navy);color:#fff;font-weight:600;text-align:right;}
.stat-table td:first-child,.stat-table th:first-child{text-align:left;}
.stat-table caption{caption-side:top;text-align:left;font-weight:300;color:var(--navy);
  font-family:'Merriweather',Georgia,serif;font-size:1.15rem;margin:2rem 0 .4rem;}
.stat-table caption:first-of-type{margin-top:.4rem;}
.table-note{font-size:.85em;color:var(--muted);margin:-.1rem 0 1.8rem;line-height:1.5;}

.site-footer{border-top:1px solid var(--border);margin-top:1rem;padding:1.4rem 1.2rem;text-align:center;
  color:var(--muted);font-size:.82rem;}
.site-footer code{font-family:ui-monospace,Menlo,monospace;background:#eef0f4;padding:.1rem .35rem;}

/* ---- raw-data page: scoped table styling -------------------------------------------------------------- */
.raw-data h2{margin:0 0 .3rem;font-family:'Merriweather',Georgia,serif;font-weight:300;color:var(--navy);
  font-size:1.5rem;}
.raw-data .src{color:var(--muted);font-size:.85em;margin:.1rem 0;font-family:ui-monospace,Menlo,monospace;}
.raw-data .desc{margin:.4rem 0 .6rem;max-width:860px;}
.raw-data .obs{font-weight:bold;margin:.3rem 0;}
.raw-data .inv{color:var(--muted);font-size:.84em;margin:.2rem 0 1rem;max-width:920px;}
.raw-data table{border-collapse:collapse;width:100%;margin:.5rem 0 1rem;font-size:.9em;}
.raw-data th{text-align:left;border:1px solid var(--border);padding:5px 8px;vertical-align:middle;}
.raw-data td{text-align:right;border:1px solid var(--border);padding:5px 8px;vertical-align:middle;}
.raw-data td.l,.raw-data .var{text-align:left;}
.raw-data .vd{font-weight:normal;color:var(--muted);font-size:.92em;}
.raw-data table.cat th{background:var(--navy);color:#fff;} .raw-data table.num th{background:var(--accent);color:#fff;}
.raw-data .note{font-size:.86em;color:#3d444d;margin:.35rem 0;line-height:1.4;}
.raw-data .dupes{font-size:.9em;margin:1rem 0 .3rem;line-height:1.4;}

@media (max-width:700px){
  .hero h1{font-size:1.9rem;}
  .site-header-inner{flex-direction:column;align-items:flex-start;}
  .site-nav{gap:.9rem;font-size:.85rem;}
}
"
