project('singularity-vector', ['vala', 'c'], version: '0.2.0', meson_version: '>= 0.59.0')

i18n = import('i18n')
gnome = import('gnome')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-vector"', language: 'c')
add_project_arguments('-w', language: 'c')
subdir('po')

cc = meson.get_compiler('c')
gtk_dep = dependency('gtk4')
gee_dep = dependency('gee-0.8')
json_dep = dependency('json-glib-1.0')
xml_dep = dependency('libxml-2.0')
zlib_dep = dependency('zlib')
lcms_dep = dependency('lcms2')
pango_dep = dependency('pangocairo')
peas_dep = dependency('libpeas-2')
math_dep = cc.find_library('m')
libsingularity_dep = dependency('singularity-1.0', fallback: ['libsingularity', 'libsingularity_dep'])
libsingularity_proj = subproject('libsingularity')
pdf_dep = libsingularity_proj.get_variable('libsingularity_pdf_dep')
tiff_pc = dependency('libtiff-4')
tiff_dep = declare_dependency(compile_args: ['-I' + tiff_pc.get_variable(pkgconfig: 'includedir')], link_args: ['-L' + tiff_pc.get_variable(pkgconfig: 'libdir'), '-ltiff'])
draw = subproject('singularity-draw')
draw_engine_dep = draw.get_variable('vector_engine_dep')

plugin_lib = shared_library('singularity-vector-plugin',
  files('plugin/vector_plugin.vala'),
  dependencies: [dependency('gio-2.0')],
  vala_header: 'singularity-vector-plugin.h',
  vala_vapi: 'singularity-vector-plugin.vapi',
  install: true,
  install_dir: [get_option('libdir'), false, false],
)
plugin_dep = declare_dependency(link_with: plugin_lib, include_directories: include_directories('.'))


core_sources = files(
  'model/paint.vala',
  'model/color_manager.vala',
  'model/vector_cms.c',
  'model/nodes.vala',
  'model/transforms.vala',
  'model/live_nodes.vala',
  'model/generated_nodes.vala',
  'model/document.vala',
  'render/raster.vala',
  'render/text_layout.vala',
  'render/renderer.vala',
  'render/brushes.vala',
  'io/native.vala',
  'io/svg_writer.vala',
  'io/svg_reader.vala',
)

io_sources = files(
  'io/formats.vala',
  'io/pdf_import.vala',
  'io/dxf.vala',
  'io/export.vala',
  'io/draw_exchange.vala',
  'io/palettes.vala',
)

ui_sources = files(
  'ui/canvas.vala',
  'ui/canvas_rulers.vala',
  'ui/inspector_panel.vala',
  'ui/commands.vala',
  'ui/forms.vala',
  'ui/paint_editor.vala',
  'ui/properties_panel.vala',
  'ui/appearance_panel.vala',
  'ui/libraries_panel.vala',
  'ui/layers_panel.vala',
  'ui/text_editor.vala',
  'ui/dialogs.vala',
  'ui/export_dialogs.vala',
  'ui/actions.vala',
  'ui/plugins.vala',
  'ui/test_script.vala',
  'ui/ribbon.vala',
  'ui/window.vala',
  'ui/app.vala',
  'tools/base.vala',
  'tools/path_edit.vala',
  'tools/drawing.vala',
  'tools/edit_tools.vala',
)

core_inc = include_directories('model')
core_args = ['--pkg', 'zlib', '--pkg', 'posix', '--vapidir=' + meson.current_source_dir() / 'vapi']
core_deps = [gtk_dep, gee_dep, json_dep, xml_dep, zlib_dep, lcms_dep, pango_dep, peas_dep, math_dep, libsingularity_dep, tiff_dep]
app_deps = core_deps + [pdf_dep, draw_engine_dep, plugin_dep]

resources = gnome.compile_resources('singularity-vector-resources', 'data/dev.sinty.vector.gresource.xml', source_dir: 'data', c_name: 'singularity_vector')

executable('singularity-vector',
  files('src/main.vala') + core_sources + io_sources + ui_sources + [resources],
  include_directories: core_inc,
  dependencies: app_deps,
  vala_args: core_args,
  install: true,
)

engine_test = executable('vector-engine-test', core_sources + files('tests/engine_test.vala'),
  include_directories: core_inc,
  dependencies: core_deps,
  vala_args: core_args,
)
test('vector-engine', engine_test, env: ['TMPDIR=' + meson.current_build_dir()])

io_test = executable('vector-io-test', core_sources + io_sources + ui_sources + [resources] + files('tests/io_test.vala'),
  include_directories: core_inc,
  dependencies: app_deps,
  vala_args: core_args,
)

star_burst = shared_module('star-burst',
  files('plugin/examples/star_burst.vala'),
  dependencies: [dependency('gio-2.0'), json_dep, peas_dep, plugin_dep, math_dep],
  install: true,
  install_dir: get_option('libdir') / 'singularity-vector' / 'plugins' / 'star-burst',
)
configure_file(input: 'plugin/examples/star-burst.plugin', output: 'star-burst.plugin', copy: true)
install_data('plugin/examples/star-burst.plugin', install_dir: get_option('libdir') / 'singularity-vector' / 'plugins' / 'star-burst')
test('vector-io', io_test, env: ['TMPDIR=' + meson.current_build_dir(), 'SINGULARITY_VECTOR_PLUGIN_PATH=' + meson.current_build_dir()], timeout: 180, depends: [star_burst])

executable('vector-showcase', core_sources + files('tests/showcase.vala'), include_directories: core_inc, dependencies: core_deps, vala_args: core_args, build_by_default: false)
executable('vector-iconsgen', core_sources + files('tests/iconsgen.vala'), include_directories: core_inc, dependencies: core_deps, vala_args: core_args, build_by_default: false)

install_data('data/dev.sinty.vector.desktop', install_dir: get_option('datadir') / 'applications')
install_data('data/dev.sinty.vector.gschema.xml', install_dir: get_option('datadir') / 'glib-2.0' / 'schemas')
install_data('data/dev.sinty.vector.json', install_dir: get_option('datadir') / 'singularity' / 'app-settings')
install_data('data/icons/dev.sinty.vector.svg', install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps')
