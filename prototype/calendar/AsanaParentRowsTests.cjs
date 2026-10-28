const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(require('node:path').join(__dirname, '../../app.js'), 'utf8');
vm.runInThisContext(source.slice(source.indexOf('function asanaTasksThisWeek('), source.indexOf('function renderSchedule(')));
const parentURL = 'https://app.asana.com/0/0/99';
const groups = groupAsanaTasks([
  {id:'a', title:'Subtask A', parent:{gid:'99',name:'Parent'}, brief:{description:'Child instructions', parentTitle:'Parent', parentURL, parentDescription:'Parent brief'}},
  {id:'b', title:'Subtask B', brief:{parentTitle:'Parent',parentURL,parentDescription:'Parent brief'}},
  {id:'c', title:'Unresolved subtask', url:'https://app.asana.com/0/0/12'},
  {id:'d', title:'Top level',url:'https://app.asana.com/0/0/99',brief:{title:'Parent',description:'Parent brief'}},
]);
assert.equal(groups.length, 1);
assert.equal(groups[0].title, 'Parent');
assert.equal(groups[0].briefTask.title, 'Parent');
assert.equal(groups[0].briefTask.url, parentURL);
assert.equal(groups[0].briefTask.brief.description, 'Parent brief');
assert.equal(groups[0].briefTask.brief.parentTitle, undefined);
assert(!JSON.stringify(groups[0].briefTask).includes('Child instructions'));
assert.equal(groupAsanaTasks([{id:'x', title:'Child', brief:{message:'Parent unavailable'}}]).length,0);
console.log('PASS: one parent row across direct/calendar metadata, unresolved subtasks hidden, parent-only brief and comment target.');

const native = fs.readFileSync(require('node:path').join(__dirname, 'AsanaBriefs.swift'), 'utf8');
assert(!native.includes('projects.gid') && !native.includes('projects.name'), 'Parent rows must not request fields requiring projects:read');

assert.equal(groups[0].subtasks.length, 2, 'Assigned parent must not appear as its own subtask');
const child = asanaSubtaskBrief(groups[0].subtasks[0]);
assert.equal(child.title, 'Subtask A');
assert.equal(child.brief.description, 'Child instructions');
assert.equal(child.brief.parentTitle, undefined, 'Individual popup shows the subtask brief');
assert.equal(asanaSubtaskBrief({title:'Undated child', description:'Instructions'}).brief.description, 'Instructions');
console.log('PASS: assigned subtask bullets exclude the parent; individual brief shows child instructions.');

const week = asanaTasksThisWeek([
  {dueDate:'2026-10-25'}, {dueDate:'2026-10-26'}, {dueDate:'2026-11-01'}, {dueDate:'2026-11-02'}, {dueDate:''}
], new Date(2026,9,28));
assert.deepEqual(week.map(t => t.dueDate), ['2026-10-26','2026-11-01']);
assert.equal(asanaTasksThisWeek([{dueDate:'2026-11-01'}], new Date(2026,10,1)).length,1);
console.log('PASS: local Monday–Sunday week, Sunday stays in current week, old/future/undated assignments excluded.');

const today = new Date(2026,9,28,23,59);
assert.equal(asanaDueUrgency('2026-10-27',today),'urgent');
assert.equal(asanaDueUrgency('2026-10-28',today),'urgent');
assert.equal(asanaDueUrgency('2026-10-29',today),'soon');
assert.equal(asanaDueUrgency('2026-10-30',today),'soon');
assert.equal(asanaDueUrgency('2026-10-31',today),'later');
assert.equal(asanaDueUrgency('2026-11-02',new Date(2026,9,31,23,59)),'soon');
console.log('PASS: due date urgency thresholds and daylight-saving boundary.');
