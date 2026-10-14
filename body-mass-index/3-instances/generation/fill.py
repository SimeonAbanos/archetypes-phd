"""Replaces the random values of an instance generated from the operational template with illustrative ones.

Usage: python fill.py <generated.xml> <instance-valid.xml>   (needs lxml)
"""
import sys
from lxml import etree

NS = 'http://schemas.openehr.org/v1'
XSI = 'http://www.w3.org/2001/XMLSchema-instance'
N = {'o': NS, 'xsi': XSI}
T = '2026-09-26T10:00:00'

src, dst = sys.argv[1], sys.argv[2]
parser = etree.XMLParser(remove_blank_text=True, remove_comments=True)
root = etree.parse(src, parser).getroot()


def one(ctx, xp):
    r = ctx.xpath(xp, namespaces=N)
    assert len(r) == 1, (xp, len(r))
    return r[0]


def drop(ctx, xp):
    for el in ctx.xpath(xp, namespaces=N):
        el.getparent().remove(el)


def obs(aid):
    return one(root, "o:content[@archetype_node_id='%s']" % aid)


# composition
one(root, 'o:territory/o:code_string').text = 'BG'
comp = one(root, 'o:composer')
for ch in list(comp):
    comp.remove(ch)
etree.SubElement(comp, '{%s}name' % NS).text = 'Demonstration'
one(root, 'o:context/o:start_time/o:value').text = T
one(root, 'o:context/o:setting/o:value').text = 'other care'
one(root, 'o:context/o:setting/o:defining_code/o:code_string').text = '238'
for v in root.xpath('.//o:origin/o:value | .//o:events/o:time/o:value', namespaces=N):
    v.text = T

# body weight: 82.0 kg, lightly clothed
w = obs('openEHR-EHR-OBSERVATION.body_weight.v2')
one(w, ".//o:items[@archetype_node_id='at0004']/o:value/o:magnitude").text = '82.0'
dress = one(w, ".//o:items[@archetype_node_id='at0009']/o:value")
one(dress, 'o:value').text = 'Lightly clothed/underwear'
one(dress, 'o:defining_code/o:code_string').text = 'at0011'
drop(w, ".//o:items[@archetype_node_id='at0024'] | .//o:items[@archetype_node_id='at0025']")

# height: 178.0 cm, standing
h = obs('openEHR-EHR-OBSERVATION.height.v2')
one(h, ".//o:items[@archetype_node_id='at0004']/o:value/o:magnitude").text = '178.0'
drop(h, ".//o:items[@archetype_node_id='at0018'] | .//o:items[@archetype_node_id='at0019']")

# body mass index: 25.9 kg/m2, calculated automatically
b = obs('openEHR-EHR-OBSERVATION.body_mass_index.v2')
q = one(b, ".//o:items[@archetype_node_id='at0004']/o:value")
one(q, 'o:magnitude').text = '25.9'
etree.SubElement(q, '{%s}precision' % NS).text = '1'
one(b, ".//o:items[@archetype_node_id='at0010']/o:value/o:value").text = 'body weight (kg) / height (m)^2'
drop(b, ".//o:items[@archetype_node_id='at0013'] | .//o:items[@archetype_node_id='at0012']")
# the state of the index carried only confounding factors
drop(b, ".//o:events/o:state")

# protocols that the generator left without items
for p in root.xpath('.//o:protocol[not(o:items)]', namespaces=N):
    p.getparent().remove(p)

etree.indent(root, space='  ')
comment = ('Generated from the operational template anthropometric_measurements.en.v0 with the CaboLabs openEHR-OPT '
           'library, then filled with illustrative values: body weight 82.0 kg measured lightly clothed, height '
           '178.0 cm standing, body mass index 25.9 kg/m2 calculated automatically. The values describe no person.')
body = etree.tostring(root, encoding='unicode')
with open(dst, 'w', encoding='utf-8', newline='\n') as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<!-- ' + comment + ' -->\n' + body + '\n')
print('written', dst)
