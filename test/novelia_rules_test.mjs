import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const sources = JSON.parse(readFileSync(new URL('../assets/sources/novelia.json', import.meta.url)));
const bookUrl = 'https://n.novelia.cc/novel/hameln/example';
const api = 'https://n.novelia.cc/api/novel/hameln/example';
const metadata = {titleJp: 'Japanese title', titleZh: 'Chinese title', authors: [{name: 'Author'}],
  introductionJp: 'Japanese intro', introductionZh: 'Chinese intro', keywords: ['Fantasy'],
  toc: [{titleJp: 'Volume', titleZh: 'Translated volume'}, {chapterId: 'a/b', titleJp: 'One', titleZh: 'Translated one'}]};

for (const source of sources) {
  test(`${source.bookSourceName}: rules fetch the chosen version without fallback`, () => {
    let chapter = {sakuraParagraphs: ['Sakura <img src="/cover.png">'], gptParagraphs: ['GPT'],
      youdaoParagraphs: ['Youdao'], paragraphs: ['Original']};
    const requests = [];
    const context = vm.createContext({source: {getVariable() { return ''; }}, java: {get(url) {
      requests.push(url);
      if (url === api) return {body() { return JSON.stringify(metadata); }};
      assert.equal(url, `${api}/chapter/a%2Fb`);
      return {body() { return JSON.stringify(chapter); }};
    }}});
    vm.runInContext(source.mainJs, context);
    const found = context.search(bookUrl, 1);
    assert.equal(found[0].bookUrl, bookUrl);
    assert.equal(found[0].name, source.bookSourceUrl.endsWith('#jp') ? 'Japanese title' : 'Chinese title');
    assert.equal(context.search(bookUrl, 2).length, 0);
    const toc = context.getChapters(found[0]);
    assert.equal(toc[0].isVolume, true);
    assert.equal(toc[1].url, `${api}/chapter/a%2Fb`);
    const content = context.getContent(toc[1], found[0], null);
    const expected = {'#sakura': 'Sakura', '#gpt': 'GPT', '#youdao': 'Youdao', '#jp': 'Original'};
    const variant = new URL(source.bookSourceUrl).hash;
    assert.ok(content.includes(expected[variant]));
    if (variant === '#sakura') assert.ok(content.includes('<img'));
    delete chapter[context.paragraphField];
    assert.throws(() => context.getContent(toc[1], found[0], null));
    assert.throws(() => context.search('https://novelia.cc.evil.test/novel/hameln/example', 1));
    assert.throws(() => context.search('http://novelia.cc/novel/hameln/example', 1));
    assert.ok(requests.every(url => url.startsWith(api)));
  });
}
