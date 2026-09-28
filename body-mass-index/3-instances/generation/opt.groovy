// Generates an instance from an operational template, or checks instances against it.
// Needs the CaboLabs openEHR-OPT library on the classpath (see README.md).
//
//   groovy opt.groovy generate <template.opt> <output.xml>
//   groovy opt.groovy validate <template.opt> <instance.xml>...

import java.nio.file.Files
import com.cabolabs.openehr.opt.parser.OperationalTemplateParser
import com.cabolabs.openehr.opt.instance_generator.XmlInstanceGenerator
import com.cabolabs.openehr.opt.instance_validation.XmlValidation
import com.cabolabs.openehr.opt.manager.OptManager
import com.cabolabs.openehr.opt.manager.OptRepositoryFSImpl
import com.cabolabs.openehr.formats.OpenEhrXmlParser
import com.cabolabs.openehr.validation.RmValidator2

if (args.length < 3 || !(args[0] in ['generate', 'validate'])) {
    println 'usage: groovy opt.groovy generate <template.opt> <output.xml>'
    println '       groovy opt.groovy validate <template.opt> <instance.xml>...'
    System.exit(1)
}
def optFile = new File(args[1])

if (args[0] == 'generate') {
    // every element the template keeps gets a random value
    def opt = new OperationalTemplateParser().parse(optFile.getText('UTF-8'))
    def xml = new XmlInstanceGenerator().generateXMLCompositionStringFromOPT(opt, false)
    new File(args[2]).setText(xml, 'UTF-8')
    println 'written ' + args[2]
    return
}

// the library loads templates from a folder, so the template is copied into a temporary one
def ns = 'kit'
def repo = Files.createTempDirectory('opt').toFile()
def nsDir = new File(repo, ns)
nsDir.mkdirs()
new File(nsDir, optFile.name).bytes = optFile.bytes
OptManager.reset()
def manager = OptManager.getInstance()
manager.init(new OptRepositoryFSImpl(repo.path), 1800, ns)
manager.loadAll(ns)

// step 1: the openEHR reference model schema that comes with the library
def schema = new XmlValidation(getClass().getResourceAsStream('/xsd/Version.xsd'))

args.drop(2).each { path ->
    def xml = new File(path).getText('UTF-8')
    println new File(path).name
    if (!schema.validate(xml)) {
        println '  step 1, reference model: invalid'
        schema.errors.each { println '    ' + it }
        return
    }
    println '  step 1, reference model: valid'
    // step 2: the constraints of the operational template
    def report = new RmValidator2(manager).dovalidate(new OpenEhrXmlParser().parseLocatable(xml), ns)
    println '  step 2, operational template: ' + (report.hasErrors() ? 'invalid' : 'valid')
    report.errors.each { println '    ' + it }
}
repo.deleteDir()
