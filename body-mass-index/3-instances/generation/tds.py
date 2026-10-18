"""Template Data Schema (TDS) for the operational template of this kit, and instances in its form.

  python tds.py schema   <template.opt> <schema.xsd>
      Writes an XML schema derived from the operational template. Its tag set comes from the
      template: a node that is one of several possible children takes its name from the text of
      the node, and a single-valued attribute of the Reference Model keeps its own name. The
      values below the template nodes keep the types of the Reference Model, from the schema in
      1-reference-model, which the TDS imports.
  python tds.py document <template.opt> <canonical.xml> <instance.xml>
      Writes a canonical openEHR XML instance of the template in the form the TDS describes.

The form follows the TDS that Template Designer of Ocean Health Systems exports (tds-default.xsl,
version 2.3):
namespace, tag names, a name element with the text of the node, the node identifier as a fixed
attribute and the identifier of the template on the root. Unlike it, the schema carries only the
structure - which nodes, in which order, how many times and of which types. The constraints on
the values (units, intervals, precision, codes) stay in the operational template and are checked
in step 2, so that the two levels of validity remain apart.

Written for this template. Needs Python 3 with lxml. Part of this kit, under its CC0 1.0 licence.
"""
import re
import sys
from lxml import etree

OE = 'http://schemas.openehr.org/v1'
T = 'http://schemas.oceanehr.com/templates'
XS = 'http://www.w3.org/2001/XMLSchema'
XSI = 'http://www.w3.org/2001/XMLSchema-instance'
NS = {'o': OE}
RM_SCHEMA = '../1-reference-model/Version.xsd'

# The attributes of each class of the Reference Model, in the order of its XML schema:
# (name, type, minOccurs, maxOccurs). LOCATABLE comes first in every archetyped class.
LOCATABLE = [('uid', 'UID_BASED_ID', 0, 1), ('links', 'LINK', 0, None),
             ('feeder_audit', 'FEEDER_AUDIT', 0, 1)]
RM = {
    'COMPOSITION': [('language', 'CODE_PHRASE', 1, 1), ('territory', 'CODE_PHRASE', 1, 1),
                    ('category', 'DV_CODED_TEXT', 1, 1), ('composer', 'PARTY_PROXY', 1, 1),
                    ('context', 'EVENT_CONTEXT', 0, 1), ('content', 'CONTENT_ITEM', 0, None)],
    'OBSERVATION': [('language', 'CODE_PHRASE', 1, 1), ('encoding', 'CODE_PHRASE', 1, 1),
                    ('subject', 'PARTY_PROXY', 1, 1), ('provider', 'PARTY_PROXY', 0, 1),
                    ('other_participations', 'PARTICIPATION', 0, None),
                    ('work_flow_id', 'OBJECT_REF', 0, 1), ('protocol', 'ITEM_STRUCTURE', 0, 1),
                    ('guideline_id', 'OBJECT_REF', 0, 1), ('data', 'HISTORY', 1, 1),
                    ('state', 'HISTORY', 0, 1)],
    'HISTORY': [('origin', 'DV_DATE_TIME', 1, 1), ('period', 'DV_DURATION', 0, 1),
                ('duration', 'DV_DURATION', 0, 1), ('events', 'EVENT', 0, None),
                ('summary', 'ITEM_STRUCTURE', 0, 1)],
    # EVENT is abstract: the attributes of INTERVAL_EVENT are optional here, and the attribute
    # "type" of the element says which of the two it is
    'EVENT': [('time', 'DV_DATE_TIME', 1, 1), ('data', 'ITEM_STRUCTURE', 1, 1),
              ('state', 'ITEM_STRUCTURE', 0, 1), ('width', 'DV_DURATION', 0, 1),
              ('sample_count', 'xs:int', 0, 1), ('math_function', 'DV_CODED_TEXT', 0, 1)],
    'ITEM_TREE': [('items', 'ITEM', 0, None)],
    'CLUSTER': [('items', 'ITEM', 1, None)],
    'ELEMENT': [('value', 'DATA_VALUE', 0, 1), ('null_flavour', 'DV_CODED_TEXT', 0, 1)],
}
EVENT_TYPES = ['POINT_EVENT', 'INTERVAL_EVENT']
ABSTRACT = {'PARTY_PROXY', 'CONTENT_ITEM', 'ITEM_STRUCTURE', 'ITEM', 'EVENT', 'DATA_VALUE',
            'OBJECT_ID', 'UID_BASED_ID'}


# ---------------------------------------------------------------- the operational template

class Node:
    def __init__(self, rm, code, archetype, text, occ, slot=False):
        self.rm, self.code, self.archetype, self.text = rm, code, archetype, text
        self.occ, self.slot = occ, slot
        self.attrs = {}        # RM attribute name -> Attr
        self.values = []       # for an ELEMENT: the RM types allowed for its value


class Attr:
    def __init__(self, name, multiple, existence, cardinality):
        self.name, self.multiple = name, multiple
        self.existence, self.cardinality = existence, cardinality
        self.children = []


def interval(e):
    if e is None:
        return None
    lo = int(e.findtext('o:lower', namespaces=NS) or 0)
    up = None if e.findtext('o:upper_unbounded', namespaces=NS) == 'true' else int(e.findtext('o:upper', namespaces=NS))
    return (lo, up)


def read_node(e, archetype, terms):
    aid = e.findtext('o:archetype_id/o:value', namespaces=NS)
    if aid:
        archetype = aid
        terms = {t.get('code'): t.findtext("o:items[@id='text']", namespaces=NS)
                 for t in e.findall('o:term_definitions', namespaces=NS)}
    rm = e.findtext('o:rm_type_name', namespaces=NS)
    code = e.findtext('o:node_id', namespaces=NS) or ''
    kind = e.get('{%s}type' % XSI)
    n = Node(rm, code, aid, terms.get(code, ''), interval(e.find('o:occurrences', namespaces=NS)),
             slot=(kind == 'ARCHETYPE_SLOT'))
    n.root = archetype
    for a in e.findall('o:attributes', namespaces=NS):
        name = a.findtext('o:rm_attribute_name', namespaces=NS)
        at = Attr(name, a.get('{%s}type' % XSI) == 'C_MULTIPLE_ATTRIBUTE',
                  interval(a.find('o:existence', namespaces=NS)),
                  interval(a.find('o:cardinality/o:interval', namespaces=NS)))
        for c in a.findall('o:children', namespaces=NS):
            if rm == 'ELEMENT' and name == 'value':
                n.values.append(c.findtext('o:rm_type_name', namespaces=NS))
                continue
            child = read_node(c, archetype, terms)
            if child.occ == (0, 0):
                continue            # the template leaves this node out
            if not (child.code or child.slot):
                continue            # a constraint on a value, not a node of the structure
            at.children.append(child)
        n.attrs[name] = at
    return n


def read_template(path):
    doc = etree.parse(path)
    r = doc.getroot()
    tid = r.findtext('o:template_id/o:value', namespaces=NS)
    root = read_node(r.find('o:definition', namespaces=NS), '', {})
    return tid, root


def tag(text):
    t = re.sub(r'[^A-Za-z0-9]+', '_', text).strip('_')
    return t if t and not t[0].isdigit() else '_' + t


def child_tags(attr):
    """The tag of each child of a multiple attribute; the node identifier tells apart equal names."""
    names = [tag(c.text) for c in attr.children]
    return [n + ('_' + c.code if names.count(n) > 1 else '') for n, c in zip(names, attr.children)]


# ---------------------------------------------------------------- schema

def write(tree, out):
    body = etree.tostring(tree, encoding='UTF-8', pretty_print=True).decode('utf-8')
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n' + body)


def xs(parent, kind, **kw):
    e = etree.SubElement(parent, '{%s}%s' % (XS, kind))
    for k, v in kw.items():
        e.set(k, str(v))
    return e


def occurs(e, lo, hi):
    if lo != 1:
        e.set('minOccurs', str(lo))
    if hi != 1:
        e.set('maxOccurs', 'unbounded' if hi is None else str(hi))


def rm_type(t):
    return t if t.startswith('xs:') else 'oe:' + t


def schema_node(parent, node, name, lo, hi):
    el = xs(parent, 'element', name=name)
    occurs(el, lo, hi)
    if node.slot:
        # a slot the template leaves open: any archetype of its class, in the form of the RM
        el.set('type', rm_type(node.rm))
        return
    ct = xs(el, 'complexType')
    seq = xs(ct, 'sequence')
    nm = xs(xs(xs(seq, 'element', name='name'), 'complexType'), 'sequence')
    xs(nm, 'element', name='value', type='xs:string', default=node.text)
    xs(nm, 'element', name='mappings', type='oe:TERM_MAPPING', minOccurs=0, maxOccurs='unbounded')
    xs(nm, 'element', name='defining_code', type='oe:CODE_PHRASE', minOccurs=0)
    for n, t, a, b in LOCATABLE:
        occurs(xs(seq, 'element', name=n, type=rm_type(t)), a, b)
    rmclass = 'EVENT' if node.rm in EVENT_TYPES else node.rm
    for n, t, a, b in RM[rmclass]:
        at = node.attrs.get(n)
        if rmclass == 'ELEMENT':
            if n == 'value':
                ch = xs(seq, 'choice')
                vt = node.values[0] if len(node.values) == 1 else 'DATA_VALUE'
                xs(ch, 'element', name='value', type=rm_type(vt))
                xs(ch, 'element', name='null_flavour', type='oe:DV_CODED_TEXT')
            continue
        if at is None or not at.children:
            occurs(xs(seq, 'element', name=n, type=rm_type(t)), a, b)
            continue
        if at.multiple:
            # each node as often as its occurrences allow; with a single node the attribute's
            # cardinality also counts
            for c, ctag in zip(at.children, child_tags(at)):
                clo, chi = c.occ or (0, None)
                if len(at.children) == 1 and at.cardinality:
                    clo = max(clo, at.cardinality[0])
                schema_node(seq, c, ctag, clo, chi)
        else:
            schema_node(seq, at.children[0], n, (at.existence or (a, 1))[0], 1)
    code = node.archetype or node.code
    xs(ct, 'attribute', name='archetype_node_id', type='oe:archetypeNodeId', fixed=code, use='required')
    if node.rm == 'EVENT':
        r = xs(xs(ct, 'attribute', name='type', use='required'), 'simpleType')
        rs = xs(r, 'restriction', base='xs:string')
        for v in EVENT_TYPES:
            xs(rs, 'enumeration', value=v)
    else:
        xs(ct, 'attribute', name='type', fixed=node.rm)
    return ct


def write_schema(opt, out):
    tid, root = read_template(opt)
    s = etree.Element('{%s}schema' % XS, nsmap={'xs': XS, None: T, 'oe': OE})
    s.set('targetNamespace', T)
    s.set('elementFormDefault', 'qualified')
    s.append(etree.Comment(
        ' Template Data Schema (TDS) derived from the operational template %s with tds.py in '
        '3-instances/generation. It follows the form of the TDS that Template Designer of Ocean '
        'Health Systems exports and carries the structure of the template; the constraints on the values are '
        'checked against the operational template. ' % tid))
    xs(s, 'import', namespace=OE, schemaLocation=RM_SCHEMA)
    ct = schema_node(s, root, tag(root.text), 1, 1)
    xs(ct, 'attribute', name='template_id', type='xs:string', fixed=tid, use='required')
    write(etree.ElementTree(s), out)


# ---------------------------------------------------------------- document

def qtype(v):
    return 'oe:' + v.split(':')[-1]


def rm_copy(src, name):
    """An attribute of the RM type: the element takes the name the TDS gives it, the content
    stays in the namespace of the Reference Model."""
    e = etree.Element('{%s}%s' % (T, name))
    e.text = src.text if len(src) == 0 else None
    for k, v in src.attrib.items():
        e.set(k, v)
    for c in src:
        e.append(requalify(c))
    return e


def requalify(src):
    if not isinstance(src.tag, str):
        return etree.Comment(src.text)
    e = etree.Element(src.tag)
    e.text = src.text if len(src) == 0 else None
    for k, v in src.attrib.items():
        e.set(k, qtype(v) if k == '{%s}type' % XSI else v)
    for c in src:
        e.append(requalify(c))
    return e


def local(e):
    return etree.QName(e).localname


def document_node(src, node, name):
    e = etree.Element('{%s}%s' % (T, name))
    e.set('archetype_node_id', src.get('archetype_node_id'))
    if node.rm == 'EVENT':
        e.set('type', src.get('{%s}type' % XSI))
    rmclass = 'EVENT' if node.rm in EVENT_TYPES else node.rm
    declared = {n: t for n, t, a, b in LOCATABLE + RM[rmclass]}
    for c in src:
        if not isinstance(c.tag, str):
            continue
        n = local(c)
        if n == 'archetype_details':
            continue                     # the template and the node identifiers stand for it
        if n == 'name':
            nm = etree.SubElement(e, '{%s}name' % T)
            for g in c:
                if local(g) == 'value':
                    etree.SubElement(nm, '{%s}value' % T).text = g.text
                else:
                    nm.append(rm_copy(g, local(g)))
            continue
        at = node.attrs.get(n)
        if at is not None and at.children:
            target = [x for x in at.children if (x.archetype or x.code) == c.get('archetype_node_id')]
            if not target:
                raise SystemExit('%s %s: not a node of the template' % (n, c.get('archetype_node_id')))
            if at.multiple:
                t = child_tags(at)[at.children.index(target[0])]
            else:
                t = n
            if target[0].slot:
                x = rm_copy(c, t)
            else:
                x = document_node(c, target[0], t)
            e.append(x)
            continue
        x = rm_copy(c, n)
        t = declared.get(n, '')
        if n == 'value' and rmclass == 'ELEMENT':
            t = node.values[0] if len(node.values) == 1 else 'DATA_VALUE'
        if t not in ABSTRACT:
            x.attrib.pop('{%s}type' % XSI, None)
        elif '{%s}type' % XSI in x.attrib:
            x.set('{%s}type' % XSI, qtype(x.get('{%s}type' % XSI)))
        e.append(x)
    return e


def write_document(opt, src, out):
    tid, root = read_template(opt)
    doc = etree.parse(src)
    r = doc.getroot()
    d = document_node(r, root, tag(root.text))
    d.set('template_id', tid)
    nd = etree.Element(d.tag, nsmap={None: T, 'oe': OE, 'xsi': XSI})
    for k, v in d.attrib.items():
        nd.set(k, v)
    nd.text = d.text
    for c in d:
        nd.append(c)
    out_tree = etree.ElementTree(nd)
    for c in reversed(list(r.itersiblings(preceding=True))):
        if isinstance(c, etree._Comment):
            nd.addprevious(etree.Comment(c.text))
    nd.addprevious(etree.Comment(' Converted with tds.py from canonical openEHR XML into the form '
                                 'defined by the TDS in 2-archetypes. '))
    etree.cleanup_namespaces(out_tree, top_nsmap={None: T, 'oe': OE, 'xsi': XSI})
    write(out_tree, out)


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == 'schema':
        write_schema(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 5 and sys.argv[1] == 'document':
        write_document(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        sys.exit(__doc__)
