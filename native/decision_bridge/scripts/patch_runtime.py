"""Enable selecting 3B output embeddings in the pinned upstream runtime."""
from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'third_party/llama.cpp'


def patch_selected_embeddings():
    """Keep regular embeddings unchanged; allow selected rows for the 3B head."""
    updates = {
        'src/llama-cparams.h': [(
            '    bool embeddings;\n',
            '    bool embeddings;\n'
            '    bool embeddings_all = true; // D1_LAB_SELECTED_EMBEDDINGS\n')],
        'src/llama-context.h': [(
            '    void set_embeddings (bool value);',
            '    void set_embeddings (bool value);\n'
            '    void set_embeddings_masked(bool value); // D1_LAB_SELECTED_EMBEDDINGS')],
        'src/llama-context.cpp': [(
            '    const bool output_all   = cparams.embeddings;',
            '    const bool output_all   = cparams.embeddings && cparams.embeddings_all; '
            '// D1_LAB_SELECTED_EMBEDDINGS'), (
            'void llama_context::set_embeddings_nextn(bool value, bool masked) {',
            'void llama_context::set_embeddings_masked(bool value) {\n'
            '    synchronize();\n'
            '    cparams.embeddings_all = !value;\n'
            '    sched_need_reserve = true;\n'
            '}\n\n'
            'void llama_context::set_embeddings_nextn(bool value, bool masked) {')],
    }
    for name, replacements in updates.items():
        path = root / name
        contents = path.read_text()
        if 'D1_LAB_SELECTED_EMBEDDINGS' in contents:
            assert all(new in contents for _, new in replacements), name
            continue
        for old, new in replacements:
            assert old in contents, name
            contents = contents.replace(old, new, 1)
        path.write_text(contents)


patch_selected_embeddings()
