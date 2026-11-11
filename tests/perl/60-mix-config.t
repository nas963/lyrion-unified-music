use strict;
use warnings;
use utf8;
use Test::More;
use Plugins::UnifiedMusic::Mix::Config;

*validate = \&Plugins::UnifiedMusic::Mix::Config::validate;
*key_for_model = \&Plugins::UnifiedMusic::Mix::Config::key_for_model;
*provider_for_model = \&Plugins::UnifiedMusic::Mix::Config::provider_for_model;
*available_models = \&Plugins::UnifiedMusic::Mix::Config::available_models;

sub good {
	return {
		primarySource => 'local',
		categories => [{ name => 'Jazz', genres => ['Bebop'] }],
		model => 'claude-haiku-5-5',
		anthropicKey => 'sk-tajna',
		%{ $_[0] || {} },
	};
}

{
	my $r = validate(good());
	ok $r->{ok}, 'ispravna podesavanja';
	is $r->{config}{trackCount}, 30, 'podrazumevani broj pesama';
	is $r->{config}{runTime}, '04:00', 'podrazumevano vreme';
	is $r->{config}{timeZone}, 'Europe/Belgrade', 'podrazumevana zona';
}

ok validate(good({ trackCount => 5 }))->{ok}, 'donja granica';
ok validate(good({ trackCount => 100 }))->{ok}, 'gornja granica';
ok !validate(good({ trackCount => 4 }))->{ok}, 'ispod granice';
ok !validate(good({ trackCount => 101 }))->{ok}, 'iznad granice';
ok !validate(good({ trackCount => 'a' }))->{ok}, 'broj nije broj';
ok !validate(good({ model => 'gpt-5' }))->{ok}, 'nepodrzan model';

{
	my $r = validate(good({ model => 'gpt-6-luna', anthropicKey => 'sk-tajna' }));
	ok !$r->{ok}, 'model bez svog kljuca';
	ok !grep({ /sk-tajna/ } @{ $r->{errors} }), 'greska ne sadrzi kljuc';
}
ok validate(good({ anthropicKey => 'sk-a', openaiKey => undef }))->{ok}, 'drugi kljuc nije obavezan';

ok !validate(good({ categories => [{ name => '  ', genres => ['a'] }] }))->{ok}, 'prazan naziv';
ok !validate(good({ categories => [{ name => 'Jazz', genres => ['a'] }, { name => ' jazz ', genres => ['b'] }] }))->{ok}, 'dupli naziv';
ok !validate(good({ categories => [{ name => 'Jazz', genres => [] }] }))->{ok}, 'bez zanrova';
ok !validate(good({ runTime => '25:00' }))->{ok}, 'neispravno vreme';
ok !validate(good({ primarySource => 'spotify' }))->{ok}, 'nepoznat primarni izvor';

{
	my $from_form = \&Plugins::UnifiedMusic::Mix::Config::categories_from_form;
	is_deeply $from_form->({ umCategoryRows => 2, umCategoryName0 => 'Prog', umCategoryGenres0 => "Prog\nProg rock", umCategoryActive0 => 'on', umCategoryName1 => '  ', umCategoryGenres1 => 'x', umCategoryName2 => 'Jazz', umCategoryGenres2 => 'Bebop' }),
		[{ name => 'Prog', genres => ['Prog', 'Prog rock'], active => 1 }, { name => 'Jazz', genres => ['Bebop'], active => 0 }], 'kategorije iz forme, prazni redovi se preskacu, kvacica';
	is_deeply $from_form->({}), [], 'prazna forma';
	my $renames = \&Plugins::UnifiedMusic::Mix::Config::category_renames;
	is_deeply $renames->({ umCategoryRows => 2,
		umCategoryName0 => 'Ambient', umCategoryOriginal0 => 'Ambiemt',
		umCategoryName1 => 'Jazz', umCategoryOriginal1 => 'Jazz',
		umCategoryName2 => 'Novo', umCategoryOriginal2 => '' }),
		[['Ambiemt', 'Ambient']], 'samo stvarne promene naziva';
	is_deeply $renames->({ umCategoryRows => 0, umCategoryName0 => '  ', umCategoryOriginal0 => 'Staro' }), [], 'brisanje nije promena naziva';
	is $from_form->({ umCategoryRows => 0, umCategoryName0 => 'A', umCategoryGenres0 => 'x', umCategoryOriginal0 => 'B' })->[0]{original}, 'B', 'forma pamti stari naziv';
	is_deeply $from_form->({ umCategoryRows => 0, umCategoryName0 => 'F', umCategoryGenres0 => 'Folk, World, & Country', umCategoryActive0 => 'on' })->[0]{genres},
		['Folk, World, & Country'], 'jedan zanr sa zarezima ostaje jedan';
	is_deeply $from_form->({ umCategoryRows => 0, umCategoryName0 => 'R', umCategoryGenres0 => "Rock, Pop\nBebop\n", umCategoryActive0 => 'on' }),
		[{ name => 'R', genres => ['Rock, Pop', 'Bebop'], active => 1 }], 'novi red cuva zarez u nazivu zanra';
	is validate(good({ categories => [{ name => 'J', genres => ['a'] }] }))->{config}{categories}[0]{active}, 1, 'stara kategorija je aktivna';
	is validate(good({ categories => [{ name => 'J', genres => ['a'], active => 0 }] }))->{config}{categories}[0]{active}, 0, 'neaktivna ostaje neaktivna';
}

is key_for_model({ model => 'gpt-6-luna', openaiKey => 'o' }), 'o', 'kljuc za openai';
is provider_for_model('claude-haiku-5-5'), 'anthropic', 'provajder anthropic';
is provider_for_model('gpt-6-luna'), 'openai', 'provajder openai';
is_deeply available_models({ anthropicKey => 'a' }),
	[{ id => 'claude-haiku-5-5', available => 1 }, { id => 'gpt-6-luna', available => 0 }], 'dostupni modeli';

done_testing;
