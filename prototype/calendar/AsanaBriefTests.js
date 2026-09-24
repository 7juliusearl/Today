(() => {
  const assert = (ok, message) => { if (!ok) throw Error(message); };
  showAsanaBrief({title:'Final edit',url:'https://app.asana.com/0/1/2',brief:{title:'Final edit',description:'',parentTitle:'Parent project',parentDescription:'Timeline\n<script>not executable</script>\nhttps://example.com/brief',parentURL:'https://app.asana.com/0/1/3'}});
  const dialog = document.getElementById('asana-brief-dialog');
  assert(dialog.open, 'Brief opens');
  assert(dialog.querySelector('h3').textContent === 'Parent task · Parent project', 'Parent displayed first');
  assert(dialog.textContent.includes('<script>not executable</script>'), 'Description preserved as text');
  assert(!dialog.querySelector('script'), 'Description cannot inject markup');
  assert(dialog.querySelector('.asana-brief-text a').href === 'https://example.com/brief', 'Reference link works');
  assert(!dialog.textContent.includes('Your task’s instructions'), 'Empty subtask omitted');
  dialog.close();
  showAsanaBrief({title:'Top level',brief:{description:'Standalone brief'}});
  assert(document.getElementById('asana-brief-dialog').textContent.includes('Standalone brief'), 'Top-level description fallback');
  return 'PASS: parent priority, empty subtask, safe text, links and standalone task';
})();
