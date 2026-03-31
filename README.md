# A language

## Grammar

```A
<program> 			::= <statement_list>

<statement_list> 	::= <statement>
				   	  | <statement> <statement_list>

<statement> 		::= <assigStatement>
					  | <addEqStatement>

<assigStatement>    ::= <identifier> "=" <expression>

<addEqStatement>	::= <identifier> "+=" <expression>

<identifier> 		::= [a-zA-Z_][a-zA-Z0-9_]*

<expression> 		::= <term>
               		  | <term> "+" <expression>
               		  | <term> "-" <expression>
					  

<term>       		::= <factor>
               		  | <factor> "*" <term>
               		  | <factor> "/" <term>

<factor>     		::= <intval>
               		  | <floatval>
               		  | <stringval>
               		  | "(" <expression> ")"
```
