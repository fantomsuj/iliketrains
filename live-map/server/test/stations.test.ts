import { test } from 'node:test';
import assert from 'node:assert/strict';
import { tidyName, normaliseName } from '../src/live/stations.ts';

test('tidyName title-cases all-caps names and drops station suffixes', () => {
  assert.equal(tidyName('SECAUCUS UPPER LEVEL'), 'Secaucus');
  assert.equal(tidyName('New York Penn Station'), 'New York Penn');
  assert.equal(tidyName('Harlem-125 St'), 'Harlem-125 St');
  assert.equal(tidyName('NEWARK PENN STATION'), 'Newark Penn');
  assert.equal(tidyName('30TH ST. PHL.'), '30th St. PHL.');
});

test('normaliseName makes operator naming variants comparable', () => {
  assert.equal(normaliseName('Penn Station'), 'penn');
  assert.equal(normaliseName('New York Penn Station'), 'new york penn');
});
