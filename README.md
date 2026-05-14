# A language

## Usage

The project includes binaries for Windows, Linux and macOS. The Odin compiler doesn't currently support linking during cross compilation, so the Linux and macOS builds will need to be linked by the user or built from source using "odin build . -o:speed".

You can run the executable from the command line with path to source file as your input. On windows, you can do:<br>
```./wot_windows_amd64.exe examples/basics.wot```<br>
or, if you have an Odin compiler:<br>
```odin run . -o:speed -- examples/basics.wot```<br>

There is one flag you can include: `-dump`. This will generate a dump of the IR the VM will execute.

### Notes

- The Odin compiler recently added some breaking changes and a new language feature which this codebase uses. This means that to build the project, you need Odin version dev-2026-04 or newer.
- This project has been developed and tested on x86-64 Windows only. I have no experience with Odins cross compilation features, and the builds for Linux and macOS aren't tested. If you try to link and run these and you encounter any problems, I suggest building from source.

## Grammar (BNF, EBNF-style)

```bnf
<program>        ::= <stmt-list>EOF
<stmt-list>      ::= { <stmt> <stmt-sep>* }   
<stmt-sep>       ::= NEWLINE | ";"

<stmt>           ::= <decl>
				  | <assign>
				  | <return>
				  | <if>
				  | <while>
				  | <block>
				  | <call-stmt>

<decl>           ::= <identifier> ":=" <expr>
				  | <identifier> "::" <expr-or-fn>
				  | <identifier> ":" <type> ( "=" <expr> | ":" <expr> )
				  | <identifier> ":" <type>

<expr-or-fn>      ::= <expr> | "fn" <fn-tail>
<fn-tail>        ::= "(" [ <params> ] ")" [ "->" <type> ] <block>
<params>         ::= <param> { "," <param> }
<param>          ::= <identifier> ":" <type>

<assign>         ::= <identifier> <assign-op> <expr>
<assign-op>      ::= "=" | "+=" | "-=" | "*=" | "/=" | "%="

<return>         ::= "return" [ <expr> ]

<if>             ::= "if" <expr> <block> [ "else" <block> ]
<while>          ::= "while" <expr> <block>
<block>          ::= "{" <stmt-list> "}"

<call-stmt>      ::= <identifier> "(" [ <args> ] ")"
<args>           ::= <expr> { "," <expr> }

<expr>           ::= <or-expr>
<or-expr>        ::= <and-expr> { "||" <and-expr> }
<and-expr>       ::= <eq-expr> { "&&" <eq-expr> }
<eq-expr>        ::= <cmp-expr> { ("==" | "!=") <cmp-expr> }
<cmp-expr>       ::= <add-expr> { ("<" | ">" | "<=" | ">=") <add-expr> }
<add-expr>       ::= <mul-expr> { ("+" | "-") <mul-expr> }
<mul-expr>       ::= <unary-expr> { ("*" | "/" | "%") <unary-expr> }
<unary-expr>     ::= ("!" | "-") <unary-expr> | <call-expr>
<call-expr>      ::= <primary> { "(" [ <args> ] ")" }
<primary>        ::= <integer>
				  | <float>
				  | "true" | "false"
				  | <identifier>
				  | <char>
				  | <string>
				  | "(" <expr> ")"

<type>           ::= "int" | "float" | "bool" | "char" | "string"

<identifier>     ::= <letter> { <letter> | <digit> }
<integer>        ::= <digit> { <digit> }
<float>          ::= <digit> { <digit> } "." <digit> { <digit> }
<string>         ::= "\"" { <string-char> | <escape> } "\""
<char>           ::= "'" <single-byte> "'"
```

## Compiler/Language features

- All the basics (math, while loops, if-else, etc.)
- Functions
- Single line comments
- Error messages with source code location and descriptive messages.

- Lexer
- Recursive decent parser
- Checker stage
  - Type checking (static typing)
  - Type inference
  - Function calls (correct arg count and types)
  - Scoping rules
  - Check conditions evaluate to boolean
- Code generation
  - Custom 32-bit instruction set
  - Optional code dump with -dump flag
- Virtual machine
  - Stack based 
  - Executes the generated code

## AI Usage

Apart from the lexer, AI was used as a tool during the whole process. Especially at later stages of development (code gen and vm), it was heavily used to prototype the data structures and some of the functions. Every line of code is still vetted and understood by me. Only part where significant mental offloading was done, was generating the BNF grammar above. This was done after development was done. At the beginning, I skecthed my own grammar (visible somewhere in git history), but after I got the hang of it, I did all the design work by implementing my ideas directly.

