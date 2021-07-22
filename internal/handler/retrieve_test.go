package handler

import (
	"reflect"
	"testing"
)

func Test_retrieveQueryParams_NormalizeGroups(t *testing.T) {
	type fields struct {
		Groups string
	}
	tests := []struct {
		name   string
		fields fields
		want   []string
	}{
		{
			name: "empty",
			fields: fields{
				Groups: "",
			},
			want: nil,
		},
		{
			name: "single",
			fields: fields{
				Groups: "One",
			},
			want: []string{"one"},
		},
		{
			name: "two",
			fields: fields{
				Groups: "oNe,twO",
			},
			want: []string{"one", "two"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := &retrieveQueryParams{
				Groups: tt.fields.Groups,
			}
			if got := p.NormalizeGroups(); !reflect.DeepEqual(got, tt.want) {
				t.Errorf("retrieveQueryParams.NormalizeGroups() = %#v, want %#v", got, tt.want)
			}
		})
	}
}
